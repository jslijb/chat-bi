import re
import hashlib
import logging

from .models import DDLChunk, ChunkType

logger = logging.getLogger(__name__)


class DDLParser:

    def parse(self, ddl_text: str) -> list[DDLChunk]:
        try:
            normalized = re.sub(r'/\*.*?\*/', ' ', ddl_text, flags=re.DOTALL)
            normalized = re.sub(r'--[^\n]*', ' ', normalized)
            normalized = re.sub(r'\s+', ' ', normalized).strip()

            pattern = re.compile(
                r'\bCREATE\b\s+\bTABLE\b\s+(?:IF\s+NOT\s+EXISTS\s+)?',
                re.IGNORECASE,
            )
            matches = list(pattern.finditer(normalized))
            if not matches:
                return []

            chunks = []
            for idx, match in enumerate(matches):
                start = match.start()
                if idx + 1 < len(matches):
                    end = matches[idx + 1].start()
                else:
                    end = len(normalized)
                ddl_stmt = normalized[start:end].strip().rstrip(';')

                table_name = self._extract_table_name(ddl_stmt)
                if not table_name:
                    continue

                column_count = self._count_columns(ddl_stmt)
                fk_count = self._count_foreign_keys(ddl_stmt)
                chunk_text = self._build_chunk_text(table_name, ddl_stmt)
                chunk_id = f"ddl::{table_name}"

                chunk = DDLChunk(
                    chunk_id=chunk_id,
                    table_name=table_name,
                    chunk_text=chunk_text,
                    column_count=column_count,
                    fk_count=fk_count,
                    chunk_type=ChunkType.ddl,
                )
                chunks.append(chunk)

            return chunks
        except Exception as e:
            logger.error(f"DDL解析失败: {e}")
            return []

    def _extract_table_name(self, ddl_statement: str) -> str:
        match = re.search(
            r'\bCREATE\b\s+\bTABLE\b\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"\[]?(\w+)[`"\]]?',
            ddl_statement,
            re.IGNORECASE,
        )
        if match:
            return match.group(1)
        return ""

    def _count_columns(self, ddl_statement: str) -> int:
        paren_match = re.search(r'\((.*)\)', ddl_statement, re.DOTALL)
        if not paren_match:
            return 0

        body = paren_match.group(1)
        lines = []
        depth = 0
        current = []
        for ch in body:
            if ch == '(':
                depth += 1
                current.append(ch)
            elif ch == ')':
                depth -= 1
                current.append(ch)
            elif ch == ',' and depth == 0:
                lines.append(''.join(current).strip())
                current = []
            else:
                current.append(ch)
        if current:
            lines.append(''.join(current).strip())

        constraint_pattern = re.compile(
            r'^\s*(?:PRIMARY\s+KEY|KEY|UNIQUE|CONSTRAINT|INDEX|CHECK|FOREIGN\s+KEY)',
            re.IGNORECASE,
        )
        column_count = 0
        for line in lines:
            if line and not constraint_pattern.match(line):
                column_count += 1

        return column_count

    def _count_foreign_keys(self, ddl_statement: str) -> int:
        return len(re.findall(r'\bFOREIGN\s+KEY\b', ddl_statement, re.IGNORECASE))

    def _build_chunk_text(self, table_name: str, ddl_statement: str) -> str:
        comment_match = re.search(
            r"(?:COMMENT\s*=?\s*['\"]|ENGINE\s*=\s*\w+\s+COMMENT\s*=?\s*['\"])(.+?)['\"]",
            ddl_statement,
            re.IGNORECASE,
        )
        comment = comment_match.group(1) if comment_match else ""

        paren_match = re.search(r'\((.*)\)', ddl_statement, re.DOTALL)
        fields = []
        if paren_match:
            body = paren_match.group(1)
            field_pattern = re.compile(r'^\s*`?(\w+)`?\s+\w+', re.IGNORECASE)
            for line in re.split(r',\s*', body):
                line = line.strip()
                fm = field_pattern.match(line)
                if fm and not re.match(r'^(?:PRIMARY|KEY|UNIQUE|CONSTRAINT|INDEX|CHECK|FOREIGN)', fm.group(1), re.IGNORECASE):
                    fields.append(fm.group(1))

        parts = [f"表:{table_name}"]
        if comment:
            parts.append(f"注释:{comment}")
        if fields:
            parts.append(f"字段:{','.join(fields)}")
        return " | ".join(parts)
