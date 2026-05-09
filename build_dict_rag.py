#!/usr/bin/env python3
# ==============================================================================
# build_dict_rag.py — 数据字典 RAG 索引构建与检索
# ==============================================================================
#
# 【重要】使用魔塔(ModelScope)作为模型源，国内下载速度快
#          核心机制: modelscope.snapshot_download() → 本地缓存 → SentenceTransformer加载本地路径
#          本地构建索引 → 上传到服务器 → 服务器仅需轻量依赖即可检索
#
# 用法:
#   === 全量构建索引（首次 / 换模型后） ===
#   python build_dict_rag.py data_dictionary.yaml
#
#   === 增量构建（新增表/字段后，无需全量重建） ===
#   python build_dict_rag.py data_dictionary.yaml --append
#
#   === 全量构建 + ER 外键补充（推荐，自动查找 ods_er.txt）===
#   python build_dict_rag.py data_dictionary.yaml --er-file ods_er.txt
#
#   === 检索测试（任意环境）===
#   python build_dict_rag.py --search "三免信用赔 用户活跃度 续保率"
#
#   === 服务器部署（无需重新构建）===
#   将生成的 dict_rag_index/ 目录整个复制到服务器 workspace 即可
#   服务器只需安装: pip install faiss-cpu numpy sentence-transformers modelscope
#
# 输出文件结构:
#   dict_rag_index/
#   ├── index.faiss       ← FAISS 向量索引（~500KB）
#   ├── idmap.pkl         ← 表名 ID 映射
#   ├── tables.json       ← 完整表结构数据（检索命中后读此文件获取字段定义）
#   ├── domains.json      ← 域信息
#   └── fk_graph.json     ← 外键图谱（正向 + 反向关联，来自 DDL FK + ods_er.txt）
#
# Token 节省效果:
#   原方式: 读 data_dictionary.yaml 全文 126KB (~35K token)
#   RAG方式: 检索 Top-5 相关表 (~5-8K token)
#   节省: ~75-85%
#
# ==============================================================================

import argparse
import json
import os
import sys
from pathlib import Path

import faiss
import numpy as np
import yaml
import re

# ============ 配置 ============

# BGE 大模型 - 中文语义匹配效果最佳（魔塔 ModelScope 镜像）
MODEL_NAME_MODELSCOPE = "AI-ModelScope/bge-large-zh-v1.5"

EMBEDDING_DIM = 1024
RAG_DIR_NAME = "dict_rag_index"


def get_embedding_model():
    """
    加载 Embedding 模型，仅通过魔塔(ModelScope)下载。
    
    关键: sentence_transformers 只认 HuggingFace 格式，要真正用魔塔下载，
          必须先调用 modelscope.snapshot_download() 把模型拉到本地缓存，
          再传本地路径给 SentenceTransformer。
    """
    from sentence_transformers import SentenceTransformer
    
    print(f"[INFO] 从魔塔(ModelScope)下载模型: {MODEL_NAME_MODELSCOPE}")
    try:
        import modelscope
        # snapshot_download 会下载到缓存目录 (~/.cache/modelscope/hub/)
        local_path = modelscope.snapshot_download(MODEL_NAME_MODELSCOPE)
        print(f"[INFO] 下载完成 → {local_path}")
        model = SentenceTransformer(local_path)
        print(f"[INFO] ✅ 加载成功")
        return model
    except ImportError:
        print("[ERROR] 请先安装依赖: pip install faiss-cpu numpy pyyaml sentence-transformers modelscope")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] 魔塔加载失败: {e}")
        print("[ERROR] 请检查网络连接或手动安装 modelscope: pip install modelscope")
        sys.exit(1)


def check_dependencies():
    """检查 Python 依赖是否已安装"""
    missing = []
    
    try:
        import faiss
    except ImportError:
        missing.append("faiss-cpu")
    
    try:
        import numpy as np
    except ImportError:
        missing.append("numpy")
    
    try:
        import yaml
    except ImportError:
        missing.append("pyyaml")
    
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        missing.append("sentence-transformers")
    
    try:
        import modelscope
    except ImportError:
        missing.append("modelscope")
    
    if missing:
        print("[ERROR] 缺少依赖包:")
        for m in missing:
            print(f"  - {m}")
        print()
        print("请执行以下命令安装:")
        print("  pip install faiss-cpu numpy pyyaml sentence-transformers modelscope")
        print()
        print("或一键安装:")
        print("  pip install -r dict_rag_requirements.txt")
        sys.exit(1)
    
    faiss_ver = getattr(faiss, "__version__", "unknown")
    print(f"[INFO] 依赖检查通过: faiss={faiss_ver}, numpy={np.__version__}")


def load_data_dict(path):
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def build_table_search_text(table_name, table_data):
    """
    将单张表的信息构建为一段可搜索的文本。
    设计原则：包含足够多的业务关键词让语义匹配准确。
    """
    comment = table_data.get("comment", "")
    pk = ", ".join(table_data.get("primary_key", []))
    columns = table_data.get("columns", {})
    
    col_parts = []
    for col_name, col_def in columns.items():
        col_comment = col_def.get("comment", "")
        if col_comment:
            col_parts.append(f"{col_name}({col_comment})")
        else:
            col_parts.append(col_name)
    
    col_summary = " ".join(col_parts[:30])
    
    # 外键关系也加入检索文本，提升 JOIN 场景匹配度
    fks = table_data.get("foreign_keys", [])
    fk_parts = []
    for fk in fks:
        fk_parts.append(f"{fk['column']}->{fk['references']}")
    
    text = f"表:{table_name} | 注释:{comment} | 主键:{pk} | 字段:{col_summary}"
    if fk_parts:
        text += f" | 关联:{', '.join(fk_parts)}"
    return text


def parse_er_file(er_path: str) -> list:
    """
    从 ods_er.txt（手写 ER 关系文档）中解析外键关系。
    
    解析格式示例:
      - N:1 → `user`（`user_id`）
      - 1:N → `user_auth`（通过 `user_id`）
      - N:1 → `policy_master`（`policy_no`）
      - 1:1 → `health_policy`（通过 `policy_no`）

    返回: [(src_table, column, dst_table), ...]
          src_table 是当前正在描述的表，dst_table 是被引用的表
    """
    if not os.path.exists(er_path):
        return []

    with open(er_path, 'r', encoding='utf-8') as f:
        content = f.read()

    relations = []
    current_table = None

    # 匹配当前描述的主表: - **`table_name`**（...）
    table_header = re.compile(r'^-\s+\*\*`(\w+)`\*\*', re.MULTILINE)

    # 匹配关系行，两种模式:
    #   1. N:1 → `ref_table`（`column`）       ← 当前表引用 ref_table
    #   2. 1:N → `ref_table`（通过 `column`）   ← ref_table 引用当前表
    #   3. 1:1 → `ref_table`（`column`/通过 `column`）
    fk_pattern = re.compile(
        r'^\s+-\s+(?:N|1):(?:N|1)\s+→\s+`(\w+)`\s*[（(]\s*`?(\w+)`?[）)]',
        re.MULTILINE
    )

    lines = content.split('\n')
    for line in lines:
        # 检测主表切换
        th = table_header.match(line)
        if th:
            current_table = th.group(1)
            continue

        if not current_table:
            continue

        # 提取 FK 关系
        fk_match = fk_pattern.match(line)
        if fk_match:
            ref_table = fk_match.group(1)
            column = fk_match.group(2)
            cardinality = re.match(r'^\s+-\s+(N|1):(N|1)', line)

            if cardinality:
                src_card, dst_card = cardinality.group(1), cardinality.group(2)
                # N:1 或 1:1 → 当前表有外键列指向 ref_table
                if dst_card == '1':
                    relations.append((current_table, column, ref_table))
                # 1:N → ref_table 有外键列指向当前表（反向）
                elif src_card == '1' and dst_card == 'N':
                    # 反向关系：ref_table 通过 column 引用 current_table
                    relations.append((ref_table, column, current_table))

    return relations


def build_fk_graph(tables: dict, er_path: str = None) -> dict:
    """
    构建外键图谱: {forward: {table: {col: ref_table}}, reverse: {table: [sources]}}
    用于检索时自动扩展关联表（JOIN 关系不丢失）。

    数据来源（优先级从高到低）:
      1. tables[].foreign_keys — 来自 data_dictionary.yaml（DDL 物理外键）
      2. ods_er.txt 解析 — 手写 ER 文档（逻辑外键 + 业务关联）
    """
    forward = {}

    # ===== 来源 1: data_dictionary.yaml 中的 foreign_keys =====
    for table_name, table_data in tables.items():
        fks = table_data.get("foreign_keys", [])
        if fks:
            forward.setdefault(table_name, {})
            for fk in fks:
                col = fk["column"]
                ref = fk.get("references", fk.get("ref_table", ""))
                ref_table = ref.split(".")[0] if "." in ref else ref
                if ref_table:
                    forward[table_name][col] = ref_table

    # ===== 来源 2: ods_er.txt fallback（当 YAML 无 FK 或补充更多逻辑关系） =====
    if er_path and os.path.exists(er_path):
        er_relations = parse_er_file(er_path)
        er_count = 0
        for src_tbl, col, dst_tbl in er_relations:
            # 跳过已存在的（YAML FK 优先）
            if src_tbl in forward and col in forward[src_tbl]:
                continue
            # 确保两张表都存在于数据字典中
            if src_tbl in tables and dst_tbl in tables:
                forward.setdefault(src_tbl, {})[col] = dst_tbl
                er_count += 1
        if er_count:
            print(f"[INFO] 从 ER 文件补充外键: {er_count} 条 (来源: {er_path})")

    # 反向图谱：谁引用了我
    reverse = {}
    for src, refs in forward.items():
        for col, dst in refs.items():
            reverse.setdefault(dst, []).append(src)

    return {"forward": forward, "reverse": reverse}


def build_rag_index(data_dict, output_dir, append=False, er_path=None):
    """构建 FAISS RAG 索引（支持全量 / 增量模式）"""
    import pickle

    rag_dir = Path(output_dir) / RAG_DIR_NAME
    rag_dir.mkdir(parents=True, exist_ok=True)
    
    tables = data_dict.get("tables", {})
    if not tables:
        print("[ERROR] data_dictionary.yaml 中没有 tables 节")
        sys.exit(1)
    
    model = get_embedding_model()

    if append:
        # ========== 增量模式 ==========
        index_path = str(rag_dir / "index.faiss")
        idmap_path = str(rag_dir / "idmap.pkl")
        tables_json_path = str(rag_dir / "tables.json")

        if not os.path.exists(index_path) or not os.path.exists(idmap_path):
            print("[WARN] --append 模式但索引文件不存在，自动切换为全量构建")
            append = False
        else:
            # 加载已有索引
            index = faiss.read_index(index_path)
            with open(idmap_path, 'rb') as f:
                existing_tables = pickle.load(f)
            with open(tables_json_path, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)

            existing_set = set(existing_tables)
            new_set = set(tables.keys())

            added = new_set - existing_set  # 新增的表
            removed = existing_set - new_set  # 已删除的表

            if not added and not removed:
                print("[INFO] 无变化，跳过重建（{} 张表)".format(len(tables)))
                return index, list(tables.keys())

            if removed:
                print("[WARN] 以下表已从数据源中删除，需全量重建: {}".format(", ".join(removed)))
                print("[INFO] 建议去掉 --append，执行全量构建")
                append = False

            if added:
                print("[INFO] 增量模式：{} 张已有，新增 {} 张".format(len(existing_set), len(added)))
                new_embeddings = []
                new_names = []

                for tname in sorted(added):
                    text = build_table_search_text(tname, tables[tname])
                    vec = model.encode([text], normalize_embeddings=True)[0]
                    new_embeddings.append(vec.astype(np.float32))
                    new_names.append(tname)

                new_vectors = np.vstack(new_embeddings)
                index.add(new_vectors)  # 追加，不清空旧的

                # 合并 idmap + tables
                all_tables = existing_tables + new_names
                existing_data.update({t: tables[t] for t in added})

                with open(idmap_path, 'wb') as f:
                    pickle.dump(all_tables, f)
                with open(tables_json_path, 'w', encoding='utf-8') as f:
                    json.dump(existing_data, f, ensure_ascii=False, indent=2)
                faiss.write_index(index, index_path)

                print("[OK] 增量完成: {} → {} 张表 (+{})".format(
                    len(existing_set), len(all_tables), len(added)))
                
                # 更新外键图谱（增量合并）
                fk_graph = build_fk_graph(existing_data, er_path=er_path)
                fk_path = str(rag_dir / "fk_graph.json")
                with open(fk_path, 'w', encoding='utf-8') as f:
                    json.dump(fk_graph, f, ensure_ascii=False, indent=2)
                fk_count = sum(len(v) for v in fk_graph["forward"].values())
                print("[INFO] 外键关系: {} 条".format(fk_count))
                
                return index, all_tables

    if not append:
        # ========== 全量构建模式 ==========
        print(f"[INFO] 共 {len(tables)} 张表，开始生成向量...")
        
        table_names = list(tables.keys())
        search_texts = []
        for tname in table_names:
            text = build_table_search_text(tname, tables[tname])
            search_texts.append(text)
        
        # 批量生成 embedding
        print(f"[INFO] 生成 embedding ({len(search_texts)} 条)...")
        embeddings = model.encode(search_texts, normalize_embeddings=True, show_progress_bar=True)
        embeddings = np.array(embeddings, dtype=np.float32)
        
        # 创建 FAISS 索引
        index = faiss.IndexFlatIP(EMBEDDING_DIM)
        index.add(embeddings)
        
        # 保存索引文件
        index_path = str(rag_dir / "index.faiss")
        faiss.write_index(index, index_path)
        print(f"[INFO] 索引已保存: {index_path} ({index.ntotal} vectors, dim={EMBEDDING_DIM})")
        
        # 保存 ID 映射
        idmap_path = str(rag_dir / "idmap.pkl")
        with open(idmap_path, 'wb') as f:
            pickle.dump(table_names, f)
        
        # 保存完整表结构数据（命中后再读这个获取字段定义）
        tables_json_path = str(rag_dir / "tables.json")
        with open(tables_json_path, 'w', encoding='utf-8') as f:
            json.dump(tables, f, ensure_ascii=False, indent=2)
        
        # 保存域信息
        domains = data_dict.get("domains", {})
        domains_path = str(rag_dir / "domains.json")
        with open(domains_path, 'w', encoding='utf-8') as f:
            json.dump(domains, f, ensure_ascii=False, indent=2)
        
        # 保存外键图谱
        fk_graph = build_fk_graph(tables, er_path=er_path)
        fk_path = str(rag_dir / "fk_graph.json")
        with open(fk_path, 'w', encoding='utf-8') as f:
            json.dump(fk_graph, f, ensure_ascii=False, indent=2)
        fk_count = sum(len(v) for v in fk_graph["forward"].values())
        print(f"[INFO] 外键关系: {fk_count} 条")
        
        # 输出目录大小统计
        total_size = sum(os.path.getsize(str(p)) for p in rag_dir.rglob("*") if p.is_file())
        print(f"[INFO] 完整表数据: {tables_json_path} ({os.path.getsize(tables_json_path)//1024} KB)")
        print(f"[INFO] ID映射: {idmap_path}")
        print(f"[INFO] 外键图谱: {fk_path}")
        print(f"[INFO] 📦 索引目录总大小: {total_size//1024} KB ({total_size//1024//1024} MB)")
        
        return index, table_names


def find_rag_index(start_dir: str = ".") -> str:
    """自动查找 dict_rag_index 目录"""
    import glob

    # 常见位置（按可能性排序）
    candidates = [
        os.path.join(start_dir, "dict_rag_index"),
        os.path.join(start_dir, "dictionaries", "dict_rag_index"),
        os.path.join(start_dir, "bi-requirement-parser", "dictionaries", "dict_rag_index"),
        # skills 子目录下的各种可能位置
        os.path.join(start_dir, ".codebuddy", "skills", "bi-requirement-parser", "dictionaries", "dict_rag_index"),
    ]

    # 递归搜索（限制前5个匹配，避免太慢）
    for pattern in ["**/dict_rag_index"]:
        try:
            matches = glob.glob(os.path.join(start_dir, pattern), recursive=True)
            candidates.extend(matches[:5])
        except Exception:
            pass

    seen = set()
    for c in candidates:
        c = os.path.normpath(c)
        if c in seen:
            continue
        seen.add(c)
        if os.path.exists(os.path.join(c, "index.faiss")):
            return c

    return None


def search_rag(query_text, output_dir, top_k=5, include_related=True):
    """使用 RAG 索引进行语义检索（支持外键关联表自动扩展）"""
    import pickle
    
    # 自动查找索引目录（支持未指定 -o 的情况）
    if output_dir and os.path.exists(os.path.join(output_dir, RAG_DIR_NAME, "index.faiss")):
        rag_dir = Path(output_dir) / RAG_DIR_NAME
    else:
        found = find_rag_index(output_dir or ".")
        if found:
            rag_dir = Path(found)
        else:
            print(f"[ERROR] 找不到 RAG 索引文件 (dict_rag_index/index.faiss)")
            print(f"[HINT] 先构建索引: python {sys.argv[0]} <data_dict.yaml> [--er-file ods_er.txt]")
            sys.exit(1)

    index_path = str(rag_dir / "index.faiss")
    idmap_path = str(rag_dir / "idmap.pkl")
    tables_json_path = str(rag_dir / "tables.json")
    fk_graph_path = str(rag_dir / "fk_graph.json")
    
    if not os.path.exists(index_path):
        print(f"[ERROR] 索引不存在，请先运行: python {sys.argv[0]} <data_dict.yaml>")
        sys.exit(1)
    
    # 加载模型和索引
    model = get_embedding_model()
    index = faiss.read_index(index_path)
    
    with open(idmap_path, 'rb') as f:
        table_names = pickle.load(f)
    
    with open(tables_json_path, 'r', encoding='utf-8') as f:
        all_tables = json.load(f)

    # 加载外键图谱
    fk_graph = {"forward": {}, "reverse": {}}
    if os.path.exists(fk_graph_path):
        with open(fk_graph_path, 'r', encoding='utf-8') as f:
            fk_graph = json.load(f)
    
    # 查询向量化
    query_embedding = model.encode([query_text], normalize_embeddings=True)
    query_embedding = np.array(query_embedding, dtype=np.float32)
    
    # 搜索（关联模式下多取一些，用于后续扩展）
    search_k = min(top_k * 2 if include_related else top_k, index.ntotal)
    scores, indices = index.search(query_embedding, search_k)
    
    # 格式化输出结果
    print(f"\n{'='*60}")
    print(f'查询: "{query_text}"')
    print(f"{'='*60}\n")
    
    matched_tables = set()
    results = []
    
    for score, idx in zip(scores[0], indices[0]):
        if idx < 0 or idx >= len(table_names):
            continue
        tname = table_names[idx]
        if tname in matched_tables:
            continue
        matched_tables.add(tname)
        
        tdata = all_tables.get(tname, {})
        
        result = {
            "table": tname,
            "score": float(score),
            "comment": tdata.get("comment", ""),
            "primary_key": tdata.get("primary_key", []),
            "columns": list(tdata.get("columns", {}).keys()),
            "column_count": len(tdata.get("columns", {})),
            "source": "direct",
        }
        results.append(result)
        
        print(f"[{result['score']:.3f}] **{tname}** -- {result['comment']}")
        print(f"   主键: {result['primary_key']}")
        print(f"   字段数: {result['column_count']}")
        cols_display = result['columns'][:10]
        print(f"   关键字段: {', '.join(cols_display)}")
        if len(result['columns']) > 10:
            print(f"   ... 等 {len(result['columns'])} 个字段")
        print()
        
        if len(matched_tables) >= top_k:
            break
    
    # 外键关联表自动扩展
    if include_related and fk_graph.get("forward"):
        related_tables = set()
        for tbl_name in matched_tables:
            # 正向：我引用了谁
            for col, ref_tbl in fk_graph["forward"].get(tbl_name, {}).items():
                if ref_tbl not in matched_tables:
                    related_tables.add((ref_tbl, f"{tbl_name}.{col} -> {ref_tbl}"))
            # 反向：谁引用了我
            for src_tbl, refs in fk_graph["forward"].items():
                for col, ref_tbl in refs.items():
                    if ref_tbl == tbl_name and src_tbl not in matched_tables:
                        related_tables.add((src_tbl, f"{src_tbl}.{col} -> {tbl_name} (被引用)"))
        
        if related_tables:
            print("关联表（自动扩展）：")
            for ref_tbl, reason in sorted(related_tables):
                rec = all_tables.get(ref_tbl, {})
                cols_count = len(rec.get("columns", {}))
                print(f"   -> **{ref_tbl}** ({cols_count}列) -- {rec.get('comment', '')} [{reason}]")
                results.append({
                    "table": ref_tbl,
                    "score": 0.0,
                    "comment": rec.get("comment", ""),
                    "columns": list(rec.get("columns", {}).keys()),
                    "column_count": cols_count,
                    "source": "related",
                    "reason": reason,
                })
            print()
    
    return results


def main():
    parser = argparse.ArgumentParser(
        description="数据字典 RAG 索引构建与检索（支持增量构建 + 外键关联扩展）",
        epilog="示例:\n"
               "  全量构建: python build_dict_rag.py data_dictionary.yaml\n"
               "  +ER外键:  python build_dict_rag.py data_dictionary.yaml --er-file ods_er.txt\n"
               "  增量构建: python build_dict_rag.py data_dictionary.yaml --append\n"
               "  检索:     python build_dict_rag.py --search '三免信用赔 用户活跃'\n"
               "  部署: 将 dict_rag_index/ 整个目录复制到服务器 ~/.openclaw/workspace/",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("input", nargs="?", default="data_dictionary.yaml", help="输入 data_dictionary.yaml 路径")
    parser.add_argument("--output-dir", "-o", default=None, help="输出目录（默认与输入同目录下的 dict_rag_index）")
    parser.add_argument("--search", "-s", default=None, help="检索模式：用自然语言查询相关表")
    parser.add_argument("--top-k", type=int, default=5, help="检索返回数量（默认5）")
    parser.add_argument("--append", action="store_true",
                        help="增量模式：只对新增表生成 embedding 并追加到索引（换模型后不可用）")
    parser.add_argument("--no-related", action="store_true",
                        help="检索时不自动扩展外键关联表")
    parser.add_argument("--er-file", "-e", default=None,
                        help="ER 关系文件路径（如 ods_er.txt），用于补充逻辑外键构建 FK 图谱")
    
    args = parser.parse_args()
    
    output_dir = args.output_dir or str(Path(args.input).parent)

    # 自动查找 ER 文件
    er_path = args.er_file
    if not er_path:
        auto_er = os.path.join(output_dir, "ods_er.txt")
        if os.path.exists(auto_er):
            er_path = auto_er
    
    if args.search:
        # 检索模式
        check_dependencies()  # 检索也需要模型
        search_rag(args.search, output_dir, top_k=args.top_k, include_related=not args.no_related)
    else:
        # 构建模式
        check_dependencies()
        
        if not os.path.exists(args.input):
            print(f"[ERROR] 找不到文件: {args.input}")
            sys.exit(1)
        
        data_dict = load_data_dict(args.input)
        table_count = len(data_dict.get("tables", {}))
        print(f"[INFO] 加载数据字典: {args.input} ({table_count} 张表)")
        
        mode_label = "增量" if args.append else "全量"
        print(f"[INFO] 模式: {mode_label}构建")
        
        build_rag_index(data_dict, output_dir, append=args.append, er_path=er_path)
        
        print(f"\n{'='*50}")
        print("[OK] RAG 索引构建完成!")
        print(f"{'='*50}")
        print(f"\n下一步操作:")
        print(f"  1. 测试检索效果:")
        print(f"     python {sys.argv[0]} --search '三免信用赔 用户活跃 续保'")
        
        if not args.append:
            print(f"\n  2. 后续新增表时使用增量构建:")
            print(f"     python {sys.argv[0]} {args.input} --append")
            
        print(f"\n  3. 部署到服务器:")
        print(f"     将整个 {RAG_DIR_NAME}/ 目录上传到服务器 ~/.openclaw/workspace/")


if __name__ == "__main__":
    main()
