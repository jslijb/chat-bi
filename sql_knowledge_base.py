"""
SQL 知识库管理脚本 (FAISS 向量库)
- 存储/检索/统计/导出 正确和错误的 SQL 示例
- 供 code-updater 和 sql-validator 调用
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import faiss
import numpy as np

# ============ 配置 ============

DEFAULT_KB_DIR = os.path.join(os.path.dirname(__file__), "knowledge", "sql_knowledge_base")
# 配置文件路径: 优先使用 config_loader (支持 ${VAR} 环境变量替换)
_CONFIG_DIR = os.path.dirname(__file__)
DEFAULT_CONFIG_PATH = os.path.join(_CONFIG_DIR, "config.yaml")
METADATA_FILE = "metadata.json"
INDEX_FILE = "index.faiss"
IDMAP_FILE = "idmap.pkl"

# 模型维度映射（按需扩展）
MODEL_DIM_MAP = {
    "BAAI/bge-large-zh-v1.5": 1024,
    "BAAI/bge-base-zh-v1.5": 768,
    "BAAI/bge-small-zh-v1.5": 512,
}


def load_kb_config(config_path: str = None) -> dict:
    """
    从 YAML 配置文件加载 embedding 相关配置。
    查找顺序：
      1. 指定的 config_path
      2. 同目录下的 kb_config.yaml
      3. 默认值（硬编码兜底）
    """
    search_paths = []
    if config_path:
        search_paths.append(config_path)
    search_paths.append(os.path.join(os.path.dirname(__file__), "kb_config.yaml"))
    search_paths.append(DEFAULT_CONFIG_PATH)

    for path in search_paths:
        p = Path(path)
        if p.exists():
            try:
                # 优先使用 config_loader (支持 ${VAR} 环境变量替换)
                try:
                    from config_loader import load_config as _load_with_env
                    cfg = _load_with_env(path)
                except ImportError:
                    import yaml
                    with open(p, "r", encoding="utf-8") as f:
                        cfg = yaml.safe_load(f) or {}
                        if "${" in str(cfg):
                            print("[WARN] 配置文件含 ${} 占位符但 config_loader 不可用，请: pip 安装或检查路径")
                
                embedding_cfg = cfg.get("embedding", {})
                print(f"[INFO] 加载配置文件: {p}")
                return {
                    "model_name": embedding_cfg.get("model_name", "BAAI/bge-large-zh-v1.5"),
                    "dim": embedding_cfg.get("dim"),
                    "config_file": str(p),
                }
            except ImportError:
                print(f"[WARN] 找到配置文件 {p}，但缺少 PyYAML，使用默认配置。请安装: pip install pyyaml")
                break
            except Exception as e:
                print(f"[WARN] 读取配置文件 {p} 失败: {e}，使用默认配置。")
                break

    return {
        "model_name": "BAAI/bge-large-zh-v1.5",
        "dim": None,
        "config_file": None,
    }


# 全局配置（启动时加载一次）
_kb_config = load_kb_config()

# ============ Embedding 模型 ============

_embedding_model = None


# 魔塔(ModelScope)镜像名映射（HuggingFace模型名 → 魔塔模型名）
MODELSCOPE_MAP = {
    "BAAI/bge-large-zh-v1.5": "AI-ModelScope/bge-large-zh-v1.5",
    "BAAI/bge-base-zh-v1.5": "AI-ModelScope/bge-base-zh-v1.5",
    "BAAI/bge-small-zh-v1.5": "AI-ModelScope/bge-small-zh-v1.5",
}


def get_embedding_model(model_name=None):
    """
    懒加载 Embedding 模型，仅通过魔塔(ModelScope)下载。
    
    核心机制: modelscope.snapshot_download() → 本地缓存 → SentenceTransformer加载本地路径
    """
    global _embedding_model
    if model_name is None:
        model_name = _kb_config["model_name"]
    if _embedding_model is None:
        from sentence_transformers import SentenceTransformer

        ms_model = MODELSCOPE_MAP.get(model_name)
        if not ms_model:
            print(f"[ERROR] 模型 {model_name} 没有对应的魔塔镜像，请在 MODELSCOPE_MAP 中添加")
            sys.exit(1)

        try:
            print(f"[INFO] 从魔塔(ModelScope)下载模型: {ms_model}")
            import modelscope
            local_path = modelscope.snapshot_download(ms_model)
            print(f"[INFO] 下载完成 → {local_path}")
            _embedding_model = SentenceTransformer(local_path)
            print(f"[INFO] ✅ 加载成功: {model_name}")
        except ImportError:
            print("[ERROR] 请先安装依赖: pip install faiss-cpu sentence-transformers modelscope")
            sys.exit(1)
        except Exception as e:
            print(f"[ERROR] 魔塔加载失败: {e}")
            print("[ERROR] 请检查网络连接或手动安装 modelscope: pip install modelscope")
            sys.exit(1)
    return _embedding_model


def embed_text(text: str, model=None) -> np.ndarray:
    """将文本转为向量"""
    if model is None:
        model = get_embedding_model()
    embedding = model.encode(text, normalize_embeddings=True)
    return np.array(embedding, dtype=np.float32).reshape(1, -1)


def build_search_text(requirement: str, tables: list, sql_text: str) -> str:
    """
    构建用于检索的文本
    格式: [需求描述] | [表名] | [SQL关键字] | [表名和字段签名]
    """
    tables_str = " ".join(tables) if tables else ""

    # 提取 SQL 关键字
    keywords = []
    sql_upper = sql_text.upper()
    for kw in ["SELECT", "INSERT", "CREATE", "ALTER", "DROP", "JOIN", "LEFT JOIN",
               "RIGHT JOIN", "INNER JOIN", "GROUP BY", "ORDER BY", "HAVING",
               "WHERE", "UNION", "WITH", "CASE WHEN", "SUM", "COUNT", "AVG",
               "MAX", "MIN", "DISTINCT", "LIMIT", "PARTITION BY", "OVER"]:
        if kw in sql_upper:
            keywords.append(kw)

    # 提取表名（FROM/JOIN 后面的词）
    import re
    table_refs = re.findall(r'(?:FROM|JOIN)\s+(\w+)', sql_text, re.IGNORECASE)
    table_refs_str = " ".join(table_refs)

    return f"{requirement} | {tables_str} | {' '.join(keywords)} | {table_refs_str}"


# ============ 知识库类 ============

class SQLKnowledgeBase:
    def __init__(self, kb_dir: str = DEFAULT_KB_DIR):
        self.kb_dir = Path(kb_dir)
        self.metadata_path = self.kb_dir / METADATA_FILE
        self.index_path = self.kb_dir / INDEX_FILE
        self.idmap_path = self.kb_dir / IDMAP_FILE

        self.kb_dir.mkdir(parents=True, exist_ok=True)
        self.records = self._load_metadata()
        self.index = self._load_index()
        self.id_map = self._load_idmap()

    def _load_metadata(self) -> list:
        """加载元数据"""
        if self.metadata_path.exists():
            with open(self.metadata_path, "r", encoding="utf-8") as f:
                return json.load(f)
        return []

    def _save_metadata(self):
        """保存元数据"""
        with open(self.metadata_path, "w", encoding="utf-8") as f:
            json.dump(self.records, f, ensure_ascii=False, indent=2)

    def _load_index(self) -> faiss.IndexFlatIP:
        """加载 FAISS 索引，维度从配置读取。模型变更时提示重建。"""
        # 优先级：配置文件 > MODEL_DIM_MAP 映射 > 从已有索引推断 > 默认 1024
        dim = None
        cfg_dim = _kb_config.get("dim")
        model_name = _kb_config["model_name"]

        if cfg_dim is not None:
            dim = cfg_dim
        elif model_name in MODEL_DIM_MAP:
            dim = MODEL_DIM_MAP[model_name]

        if self.index_path.exists():
            index = faiss.read_index(str(self.index_path))
            
            # 检查维度是否匹配（换模型后维度必然变）
            if dim is not None and index.d != dim:
                print(f"\n{'!'*60}")
                print(f"[ERROR] ⚠️  模型已更换！索引维度不兼容！")
                print(f"  当前模型: {model_name} (dim={dim})")
                print(f"  旧索引维度: {index.d} (可能是旧模型生成的)")
                print(f"  索引文件: {self.index_path}")
                print(f"\n  请重建索引:")
                print(f"    1. 导出已有数据: python sql_knowledge_base.py export -o kb_backup.json")
                print(f"    2. 删除旧索引:   rm {self.index_path} {self.idmap_path}")
                print(f"    3. 重新导入:     python sql_knowledge_base.py import -i kb_backup.json")
                print(f"{'!'*60}\n")
                sys.exit(1)
            
            print(f"[INFO] 加载索引: {self.index_path} (vectors: {index.ntotal}, dim={index.d}, model={model_name})")
            return index

        if dim is None:
            dim = 1024  # bge-large-zh-v1.5 默认维度
        print(f"[INFO] 创建新索引 (model={model_name}, dim={dim})")
        return faiss.IndexFlatIP(dim)

    def _save_index(self):
        """保存 FAISS 索引"""
        faiss.write_index(self.index, str(self.index_path))

    def _load_idmap(self) -> list:
        """加载 ID 映射"""
        if self.idmap_path.exists():
            import pickle
            with open(self.idmap_path, "rb") as f:
                return pickle.load(f)
        return []

    def _save_idmap(self):
        """保存 ID 映射"""
        import pickle
        with open(self.idmap_path, "wb") as f:
            pickle.dump(self.id_map, f)

    def add(self, sql_text: str, record_type: str, requirement: str = "",
            tables: list = None, sql_type: str = "DML", error_message: str = "",
            correct_sql: str = "", lesson: str = "", requirement_id: str = "") -> str:
        """
        添加一条 SQL 记录到知识库

        Args:
            sql_text: SQL 全文
            record_type: "correct" / "error" / "corrected"
            requirement: 需求描述
            tables: 使用的表列表
            sql_type: DDL / DML / ETL
            error_message: 错误信息（type=error 时）
            correct_sql: 修正后的 SQL（type=error 时）
            lesson: 教训总结
            requirement_id: 关联需求编号

        Returns:
            记录 ID
        """
        record_id = f"sqlkb_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{len(self.records):04d}"
        tables = tables or []

        # 构建搜索文本并生成 embedding
        search_text = build_search_text(requirement, tables, sql_text)
        embedding = embed_text(search_text)

        # 创建记录
        record = {
            "id": record_id,
            "sql_text": sql_text,
            "type": record_type,
            "requirement": requirement,
            "tables_used": tables,
            "sql_type": sql_type,
            "error_message": error_message if error_message else None,
            "correct_sql": correct_sql if correct_sql else None,
            "lesson": lesson if lesson else None,
            "requirement_id": requirement_id,
            "created_at": datetime.now().isoformat()
        }

        # 存储元数据
        self.records.append(record)
        self._save_metadata()

        # 存储向量
        self.index.add(embedding)
        self.id_map.append(record_id)
        self._save_index()
        self._save_idmap()

        type_icon = {"correct": "✅", "error": "❌", "corrected": "🔧"}.get(record_type, "?")
        print(f"[OK] {type_icon} 已入库: {record_id} ({record_type})")
        return record_id

    def search(self, requirement: str = "", tables: list = None, sql_text: str = "",
               sql_type: str = "", top_n: int = 5) -> list:
        """
        搜索相似的 SQL 记录

        Args:
            requirement: 需求描述
            tables: 表名列表
            sql_text: SQL 文本（可选，用于更精确的匹配）
            sql_type: 过滤 SQL 类型
            top_n: 返回条数

        Returns:
            匹配的记录列表
        """
        if self.index.ntotal == 0:
            print("[INFO] 知识库为空，无检索结果")
            return []

        tables = tables or []

        # 构建查询文本
        query_text = build_search_text(requirement, tables, sql_text or "")
        query_embedding = embed_text(query_text)

        # FAISS 搜索
        scores, indices = self.index.search(query_embedding, min(top_n * 3, self.index.ntotal))

        # 收集结果并按类型分组
        correct_results = []
        error_results = []

        for score, idx in zip(scores[0], indices[0]):
            if idx < 0 or idx >= len(self.id_map):
                continue
            record_id = self.id_map[idx]
            record = next((r for r in self.records if r["id"] == record_id), None)
            if record is None:
                continue

            # 过滤 SQL 类型
            if sql_type and record.get("sql_type") != sql_type:
                continue

            record["_score"] = float(score)
            if record["type"] in ("correct", "corrected"):
                correct_results.append(record)
            elif record["type"] == "error":
                error_results.append(record)

        # 各取 top 3
        results = []
        results.extend(sorted(correct_results, key=lambda x: x["_score"], reverse=True)[:3])
        results.extend(sorted(error_results, key=lambda x: x["_score"], reverse=True)[:3])

        # 按相似度排序
        results.sort(key=lambda x: x["_score"], reverse=True)

        return results[:top_n]

    def stats(self) -> dict:
        """知识库统计"""
        total = len(self.records)
        correct = sum(1 for r in self.records if r["type"] == "correct")
        error = sum(1 for r in self.records if r["type"] == "error")
        corrected = sum(1 for r in self.records if r["type"] == "corrected")
        tables = set()
        for r in self.records:
            tables.update(r.get("tables_used", []))

        return {
            "total": total,
            "correct": correct,
            "error": error,
            "corrected": corrected,
            "unique_tables": len(tables),
            "tables": sorted(tables)
        }

    def export(self, output_path: str):
        """导出知识库为 JSON"""
        export_data = {
            "export_time": datetime.now().isoformat(),
            "records": self.records,
            "stats": self.stats()
        }
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(export_data, f, ensure_ascii=False, indent=2)
        print(f"[OK] 已导出到: {output_path} ({len(self.records)} 条记录)")

    def import_from_json(self, input_path: str):
        """从 JSON 导入知识库"""
        with open(input_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        records = data.get("records", [])
        count = 0
        for record in records:
            # 检查是否已存在
            existing_ids = {r["id"] for r in self.records}
            if record["id"] in existing_ids:
                continue

            # 生成 embedding
            search_text = build_search_text(
                record.get("requirement", ""),
                record.get("tables_used", []),
                record.get("sql_text", "")
            )
            embedding = embed_text(search_text)

            self.records.append(record)
            self.index.add(embedding)
            self.id_map.append(record["id"])
            count += 1

        self._save_metadata()
        self._save_index()
        self._save_idmap()
        print(f"[OK] 导入 {count} 条新记录 (跳过 {len(records) - count} 条重复)")


# ============ 格式化输出 ============

def format_search_results(results: list) -> str:
    """将搜索结果格式化为 Markdown"""
    if not results:
        return "## 📚 SQL 知识库检索结果\n\n（知识库为空，暂无历史参考）\n"

    output = "## 📚 SQL 知识库检索结果\n\n"

    correct_examples = [r for r in results if r["type"] in ("correct", "corrected")]
    error_examples = [r for r in results if r["type"] == "error"]

    if correct_examples:
        output += "### ✅ 正确示例（建议参考）\n\n"
        for r in correct_examples:
            output += f"**需求**：{r.get('requirement', '未记录')}\n"
            output += f"```sql\n{r['sql_text']}\n```\n"
            output += f"**评价**：{'已修正后验证通过' if r['type'] == 'corrected' else '已在集群验证通过'}\n"
            output += f"**表**：{', '.join(r.get('tables_used', []))}\n"
            output += f"**相似度**：{r.get('_score', 0):.2f}\n\n"

    if error_examples:
        output += "### ❌ 错误示例（注意避坑）\n\n"
        for r in error_examples:
            output += f"**需求**：{r.get('requirement', '未记录')}\n"
            output += f"```sql\n{r['sql_text']}\n```\n"
            if r.get("error_message"):
                output += f"**错误**：`{r['error_message']}`\n"
            if r.get("correct_sql"):
                output += f"**修正**：\n```sql\n{r['correct_sql']}\n```\n"
            if r.get("lesson"):
                output += f"**教训**：{r['lesson']}\n"
            output += f"**相似度**：{r.get('_score', 0):.2f}\n\n"

    # 汇总建议
    tips = []
    all_tables = set()
    for r in results:
        all_tables.update(r.get("tables_used", []))

    if all_tables:
        tips.append(f"表名使用完整前缀：{'、'.join(sorted(all_tables))}")

    sql_types = set(r.get("sql_type", "") for r in results if r.get("sql_type"))
    if sql_types:
        tips.append(f"SQL 类型：{'、'.join(sorted(sql_types))}")

    if tips:
        output += "### 💡 写 SQL 建议\n\n"
        for i, tip in enumerate(tips, 1):
            output += f"{i}. {tip}\n"

    return output


def format_stats(stats: dict) -> str:
    """格式化统计信息"""
    output = "## 📊 SQL 知识库统计\n\n"
    output += f"| 指标 | 数量 |\n|------|------|\n"
    output += f"| ✅ 正确 SQL | {stats['correct']} |\n"
    output += f"| ❌ 错误 SQL | {stats['error']} |\n"
    output += f"| 🔧 修正 SQL | {stats['corrected']} |\n"
    output += f"| **总计** | **{stats['total']}** |\n"
    output += f"| 涉及表 | {stats['unique_tables']} |\n"
    output += f"\n**涉及的表**：{', '.join(stats['tables'][:20])}"
    if len(stats["tables"]) > 20:
        output += f" ... 等 {len(stats['tables'])} 张表"
    return output


# ============ CLI ============

def main():
    parser = argparse.ArgumentParser(description="SQL 知识库管理 (FAISS)")
    subparsers = parser.add_subparsers(dest="command", help="子命令")

    # search
    p_search = subparsers.add_parser("search", help="搜索相似 SQL")
    p_search.add_argument("--requirement", "-r", help="需求描述")
    p_search.add_argument("--tables", "-t", help="表名列表（逗号分隔）")
    p_search.add_argument("--sql", "-s", help="SQL 文本")
    p_search.add_argument("--sql-type", choices=["DDL", "DML", "ETL"], help="SQL 类型")
    p_search.add_argument("--top-n", type=int, default=5, help="返回条数")
    p_search.add_argument("--kb-dir", default=DEFAULT_KB_DIR, help="知识库目录")

    # add
    p_add = subparsers.add_parser("add", help="添加 SQL 记录")
    p_add.add_argument("--type", choices=["correct", "error", "corrected"], required=True)
    p_add.add_argument("--sql", "-s", required=True, help="SQL 文本")
    p_add.add_argument("--requirement", "-r", default="", help="需求描述")
    p_add.add_argument("--tables", "-t", default="", help="表名列表（逗号分隔）")
    p_add.add_argument("--sql-type", default="DML", choices=["DDL", "DML", "ETL"])
    p_add.add_argument("--error", "-e", default="", help="错误信息")
    p_add.add_argument("--correct-sql", "-c", default="", help="修正后的 SQL")
    p_add.add_argument("--lesson", "-l", default="", help="教训总结")
    p_add.add_argument("--req-id", default="", help="关联需求编号")
    p_add.add_argument("--kb-dir", default=DEFAULT_KB_DIR, help="知识库目录")

    # stats
    p_stats = subparsers.add_parser("stats", help="查看统计")
    p_stats.add_argument("--kb-dir", default=DEFAULT_KB_DIR, help="知识库目录")

    # export
    p_export = subparsers.add_parser("export", help="导出知识库")
    p_export.add_argument("--output", "-o", required=True, help="输出文件路径")
    p_export.add_argument("--kb-dir", default=DEFAULT_KB_DIR, help="知识库目录")

    # import
    p_import = subparsers.add_parser("import", help="导入知识库")
    p_import.add_argument("--input", "-i", required=True, help="输入文件路径")
    p_import.add_argument("--kb-dir", default=DEFAULT_KB_DIR, help="知识库目录")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    kb = SQLKnowledgeBase(args.kb_dir)

    if args.command == "search":
        tables = [t.strip() for t in args.tables.split(",")] if args.tables else []
        results = kb.search(
            requirement=args.requirement or "",
            tables=tables,
            sql_text=args.sql or "",
            sql_type=args.sql_type or "",
            top_n=args.top_n
        )
        print(format_search_results(results))

    elif args.command == "add":
        tables = [t.strip() for t in args.tables.split(",") if t.strip()] if args.tables else []
        kb.add(
            sql_text=args.sql,
            record_type=args.type,
            requirement=args.requirement,
            tables=tables,
            sql_type=args.sql_type,
            error_message=args.error,
            correct_sql=args.correct_sql,
            lesson=args.lesson,
            requirement_id=args.req_id
        )

    elif args.command == "stats":
        stats = kb.stats()
        print(format_stats(stats))

    elif args.command == "export":
        kb.export(args.output)

    elif args.command == "import":
        kb.import_from_json(args.input)


if __name__ == "__main__":
    main()
