import argparse
import json
import sys
from pathlib import Path

from .rag_gateway import RAGGateway

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
_DICT_DIR = _PROJECT_ROOT / "bi-requirement-parser" / "dictionaries"


def _resolve_path(p: str, base: Path = _PROJECT_ROOT) -> str:
    if not p:
        return ""
    fp = Path(p)
    if fp.is_absolute():
        return str(fp)
    return str((base / fp).resolve())


def main():
    parser = argparse.ArgumentParser(description="RAG系统升级版")
    sub = parser.add_subparsers(dest="command")

    build_parser = sub.add_parser("build")
    build_parser.add_argument("--yaml", default="", help="数据字典YAML路径(默认项目内置)")
    build_parser.add_argument("--ddl", default="", help="DDL文件路径(默认项目内置)")
    build_parser.add_argument("--sql-dir", default="", help="SQL目录路径")
    build_parser.add_argument("--er-file", default="", help="ER关系文件路径(默认项目内置)")
    build_parser.add_argument("--index-dir", default="", help="索引输出目录")
    build_parser.add_argument("--config", default="", help="配置文件路径")

    search_parser = sub.add_parser("search")
    search_parser.add_argument("--query", required=True)
    search_parser.add_argument("--top-k", type=int, default=5)
    search_parser.add_argument("--no-related", action="store_true")
    search_parser.add_argument("--index-dir", default="")
    search_parser.add_argument("--config", default="")
    search_parser.add_argument("--compatible", action="store_true")

    sub.add_parser("stats")
    parser.add_argument("--config", default="")

    args = parser.parse_args()

    if args.command == "build":
        config_path = args.config
        if args.index_dir:
            config_path = _ensure_config(args.index_dir, config_path)
        gw = RAGGateway(config_path)

        yaml_path = args.yaml or str(_DICT_DIR / "data_dictionary.yaml")
        er_file = args.er_file or str(_DICT_DIR / "ods_er.txt")
        ddl_path = args.ddl or str(_PROJECT_ROOT / "create_table.sql")
        sql_dir = args.sql_dir or str(_PROJECT_ROOT / "workspace" / "dwd")

        yaml_path = _resolve_path(yaml_path)
        er_file = _resolve_path(er_file)
        ddl_path = _resolve_path(ddl_path)
        sql_dir = _resolve_path(sql_dir)

        gw.build(
            yaml_path=yaml_path,
            ddl_path=ddl_path,
            sql_dir=sql_dir,
            er_file=er_file,
        )
        print("构建完成")

    elif args.command == "search":
        config_path = args.config
        if args.index_dir:
            config_path = _ensure_config(args.index_dir, config_path)
        gw = RAGGateway(config_path)
        gw.load()
        include_related = not args.no_related
        if args.compatible:
            results = gw.search_compatible(args.query, top_k=args.top_k, include_related=include_related)
        else:
            raw = gw.search(args.query, top_k=args.top_k, include_related=include_related)
            results = [r.to_dict() for r in raw]
        print(json.dumps(results, ensure_ascii=False, indent=2))

    elif args.command == "stats":
        config_path = getattr(args, "config", "")
        gw = RAGGateway(config_path)
        gw.load()
        info = gw.stats()
        print(json.dumps(info, ensure_ascii=False, indent=2))

    else:
        parser.print_help()
        sys.exit(1)


def _ensure_config(index_dir: str, config_path: str) -> str:
    if config_path:
        return config_path
    return ""


if __name__ == "__main__":
    main()
