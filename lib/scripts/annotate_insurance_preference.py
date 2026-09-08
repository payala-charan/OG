#!/usr/bin/env python3
"""Insert a rich-text Claude Insurances column without corrupting formula refs."""

from __future__ import annotations

import json
import re
import sys
from copy import copy

from openpyxl import load_workbook
from openpyxl.cell.rich_text import CellRichText, TextBlock
from openpyxl.cell.text import InlineFont
from openpyxl.styles.colors import Color
from openpyxl.utils import get_column_letter

CELL_REF = re.compile(r"(\$?)([A-Z]{1,3})(\$?)(\d{1,7})")
COLORS = {
    "black": "000000",
    "red": "FF0000",
    "yellow": "FFC000",
}


def column_index(letters: str) -> int:
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n


def column_letters(index: int) -> str:
    chars = []
    n = index
    while n > 0:
        n, rem = divmod(n - 1, 26)
        chars.append(chr(65 + rem))
    return "".join(reversed(chars))


def shift_formula(formula: str, insert_col: int) -> str:
    def repl(match: re.Match) -> str:
        abs_col, letters, abs_row, row = match.groups()
        idx = column_index(letters)
        if idx >= insert_col:
            letters = column_letters(idx + 1)
        return f"{abs_col}{letters}{abs_row}{row}"

    return CELL_REF.sub(repl, formula)


def copy_cell(source, target) -> None:
    target.value = source.value
    if source.has_style:
        target.font = copy(source.font)
        target.border = copy(source.border)
        target.fill = copy(source.fill)
        target.number_format = source.number_format
        target.protection = copy(source.protection)
        target.alignment = copy(source.alignment)
    if source.hyperlink:
        target.hyperlink = copy(source.hyperlink)
    if source.comment:
        target.comment = copy(source.comment)


def shift_columns(ws, insert_col: int) -> None:
    max_col = ws.max_column or 1
    max_row = ws.max_row or 1

    for col in range(max_col, insert_col - 1, -1):
        dest_col = col + 1
        for row in range(1, max_row + 1):
            copy_cell(ws.cell(row=row, column=col), ws.cell(row=row, column=dest_col))
        src_letter = get_column_letter(col)
        dest_letter = get_column_letter(dest_col)
        src_dim = ws.column_dimensions[src_letter]
        ws.column_dimensions[dest_letter].width = src_dim.width

    for row in range(1, max_row + 1):
        cell = ws.cell(row=row, column=insert_col)
        cell.value = None

    shifted = []
    for merged in list(ws.merged_cells.ranges):
        min_col, min_row, max_col_m, max_row_m = merged.min_col, merged.min_row, merged.max_col, merged.max_row
        if max_col_m < insert_col:
            shifted.append(str(merged))
            continue
        if min_col >= insert_col:
            min_col += 1
            max_col_m += 1
        elif max_col_m >= insert_col:
            max_col_m += 1
        shifted.append(f"{get_column_letter(min_col)}{min_row}:{get_column_letter(max_col_m)}{max_row_m}")
    ws.merged_cells.ranges.clear()
    for ref in shifted:
        ws.merge_cells(ref)

    for row in range(1, max_row + 1):
        for col in range(1, (ws.max_column or 1) + 1):
            cell = ws.cell(row=row, column=col)
            if cell.data_type == "f" and cell.value:
                cell.value = shift_formula(str(cell.value), insert_col)


def write_rich_text(cell, runs) -> None:
    blocks = []
    for run in runs:
        color = COLORS.get(run.get("color"), "000000")
        font = InlineFont(color=Color(rgb=color))
        blocks.append(TextBlock(font, run.get("text") or ""))
    cell.value = CellRichText(blocks)


def annotate(payload: dict) -> None:
    wb = load_workbook(payload["input_path"])
    for sheet_spec in payload.get("sheets", []):
        name = sheet_spec["name"]
        if name not in wb.sheetnames:
            continue
        ws = wb[name]
        insert_col = int(sheet_spec["insert_col"])
        header_row = int(sheet_spec.get("header_row") or 1)
        shift_columns(ws, insert_col)
        header = ws.cell(row=header_row, column=insert_col)
        header.value = payload.get("column_name") or "Claude Insurances"
        header.font = copy(header.font)
        for cell_spec in sheet_spec.get("cells", []):
            runs = cell_spec.get("runs") or []
            dest = ws.cell(row=int(cell_spec["row"]), column=insert_col)
            if runs:
                write_rich_text(dest, runs)
            else:
                dest.value = None
        dest_letter = get_column_letter(insert_col)
        if not ws.column_dimensions[dest_letter].width:
            ws.column_dimensions[dest_letter].width = 60

    wb.save(payload["output_path"])


def main() -> int:
    payload = json.load(sys.stdin)
    annotate(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
