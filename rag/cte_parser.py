import re
import logging
from typing import Optional

from .models import CTEChunk, ChunkType

logger = logging.getLogger(__name__)


class CTEParser:

    def parse(self, sql_text: str, etl_id: str = "") -> list[CTEChunk]:
        try:
            normalized = self._normalize_sql(sql_text)
            with_match = re.search(r'\bWITH\b\s+(?:RECURSIVE\s+)?', normalized, re.IGNORECASE)
            if not with_match:
                return []

            is_recursive = bool(re.search(r'\bWITH\b\s+RECURSIVE\b', normalized, re.IGNORECASE))
            with_start = with_match.start()
            after_with = with_match.end()

            cte_list = self._split_ctes(normalized[after_with:])
            if not cte_list:
                return []

            with_clause_end = self._find_with_clause_end(normalized, after_with, cte_list)
            assembly_select = self._extract_assembly_select(normalized, with_clause_end)

            all_cte_names = {name for name, _ in cte_list}
            chunks = []

            for idx, (cte_name, cte_body) in enumerate(cte_list):
                depends_on_tables, depends_on_ctes, output_fields = self._extract_dependencies(
                    cte_body, all_cte_names
                )
                chunk = CTEChunk(
                    chunk_id=f"{etl_id}::{cte_name}" if etl_id else cte_name,
                    cte_name=cte_name,
                    etl_id=etl_id,
                    chunk_text=cte_body.strip(),
                    depends_on_tables=depends_on_tables,
                    depends_on_ctes=depends_on_ctes,
                    output_fields=output_fields,
                    chunk_type=ChunkType.cte,
                )
                chunks.append(chunk)

            if assembly_select:
                depends_on_tables, depends_on_ctes, output_fields = self._extract_dependencies(
                    assembly_select, all_cte_names
                )
                assembly_chunk = CTEChunk(
                    chunk_id=f"{etl_id}::__assembly__" if etl_id else "__assembly__",
                    cte_name="__assembly__",
                    etl_id=etl_id,
                    chunk_text=assembly_select.strip(),
                    depends_on_tables=depends_on_tables,
                    depends_on_ctes=depends_on_ctes,
                    output_fields=output_fields,
                    chunk_type=ChunkType.assembly,
                )
                chunks.append(assembly_chunk)

            return chunks
        except Exception as e:
            logger.error(f"CTE解析失败: {e}")
            return []

    def _normalize_sql(self, sql_text: str) -> str:
        sql = re.sub(r'/\*.*?\*/', ' ', sql_text, flags=re.DOTALL)
        sql = re.sub(r'--[^\n]*', ' ', sql)
        sql = re.sub(r'\s+', ' ', sql).strip()
        return sql

    def _find_with_clause_end(self, normalized: str, after_with: int, cte_list: list) -> int:
        pos = after_with
        for _, cte_body in cte_list:
            body_start = normalized.find(cte_body.strip()[0] if cte_body.strip() else '(', pos)
            if body_start == -1:
                continue
            depth = 0
            i = body_start
            found_as = False
            while i < len(normalized):
                ch = normalized[i]
                if not found_as:
                    if ch == '(':
                        found_as = True
                        depth = 1
                    i += 1
                    continue
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
                    if depth == 0:
                        pos = i + 1
                        break
                i += 1
            else:
                pos = i
        return pos

    def _split_ctes(self, with_body: str) -> list[tuple[str, str]]:
        result = []
        pattern = re.compile(r'(\w+)\s+AS\s*\(', re.IGNORECASE)
        matches = list(pattern.finditer(with_body))
        if not matches:
            return []

        for idx, match in enumerate(matches):
            cte_name = match.group(1)
            paren_start = match.end() - 1
            depth = 0
            body_end = paren_start
            for i in range(paren_start, len(with_body)):
                ch = with_body[i]
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
                    if depth == 0:
                        body_end = i
                        break
            cte_body = with_body[paren_start + 1:body_end]
            result.append((cte_name, cte_body))

        return result

    def _extract_assembly_select(self, sql_text: str, with_end_pos: int) -> str:
        if with_end_pos >= len(sql_text):
            return ""
        remainder = sql_text[with_end_pos:].strip()
        if remainder and re.match(r'\bSELECT\b', remainder, re.IGNORECASE):
            return remainder
        return ""

    def _extract_dependencies(self, cte_body: str, all_cte_names: set[str]) -> tuple[list[str], list[str], list[str]]:
        depends_on_tables = []
        depends_on_ctes = []
        seen = set()

        from_join_pattern = re.compile(r'(?:FROM|JOIN)\s+(\w+)', re.IGNORECASE)
        for match in from_join_pattern.finditer(cte_body):
            ident = match.group(1)
            if ident.upper() in ('SELECT', 'WHERE', 'ON', 'AND', 'OR', 'AS', 'SET', 'INTO', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'CROSS', 'FULL', 'NATURAL', 'USING', 'GROUP', 'ORDER', 'HAVING', 'LIMIT', 'UNION', 'EXCEPT', 'INTERSECT', 'NOT', 'EXISTS', 'IN', 'BETWEEN', 'LIKE', 'IS', 'NULL', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'WITH', 'RECURSIVE', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'DROP', 'ALTER', 'TABLE', 'INDEX', 'VIEW', 'IF', 'VALUES', 'DISTINCT', 'ALL', 'ANY', 'SOME'):
                continue
            if ident in seen:
                continue
            seen.add(ident)
            if ident in all_cte_names:
                depends_on_ctes.append(ident)
            else:
                depends_on_tables.append(ident)

        output_fields = self._extract_output_fields(cte_body)

        return depends_on_tables, depends_on_ctes, output_fields

    def _extract_output_fields(self, cte_body: str) -> list[str]:
        select_match = re.search(r'\bSELECT\b\s+(.*?)\bFROM\b', cte_body, re.IGNORECASE | re.DOTALL)
        if not select_match:
            select_match = re.search(r'\bSELECT\b\s+(.*)', cte_body, re.IGNORECASE | re.DOTALL)
        if not select_match:
            return []

        fields_str = select_match.group(1).strip()
        if fields_str == '*':
            return ['*']

        fields = []
        depth = 0
        current = []
        for ch in fields_str:
            if ch == '(':
                depth += 1
                current.append(ch)
            elif ch == ')':
                depth -= 1
                current.append(ch)
            elif ch == ',' and depth == 0:
                field = ''.join(current).strip()
                if field:
                    alias_match = re.search(r'(?:\bAS\b\s+)?(\w+)\s*$', field, re.IGNORECASE)
                    if alias_match:
                        fields.append(alias_match.group(1))
                    else:
                        parts = field.split('.')
                        fields.append(parts[-1].strip())
                current = []
            else:
                current.append(ch)

        if current:
            field = ''.join(current).strip()
            if field:
                alias_match = re.search(r'(?:\bAS\b\s+)?(\w+)\s*$', field, re.IGNORECASE)
                if alias_match:
                    fields.append(alias_match.group(1))
                else:
                    parts = field.split('.')
                    fields.append(parts[-1].strip())

        return fields
