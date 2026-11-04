#!/usr/bin/env python3
"""Generate the two-page English Product Decision Memo PDF."""

from __future__ import annotations

from pathlib import Path
import shutil

from pypdf import PdfReader
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
TEMP_DIR = ROOT / "tmp" / "pdfs"
TEMP_PDF = TEMP_DIR / "product_decision_memo.pdf"
OUTPUT_PDF = ROOT / "docs" / "product_decision_memo.pdf"

PAGE_WIDTH, PAGE_HEIGHT = letter
LEFT_MARGIN = 0.58 * inch
RIGHT_MARGIN = 0.58 * inch
TOP_MARGIN = 0.48 * inch
BOTTOM_MARGIN = 0.48 * inch
CONTENT_WIDTH = PAGE_WIDTH - LEFT_MARGIN - RIGHT_MARGIN

NAVY = colors.HexColor("#101B29")
INK = colors.HexColor("#1E2D3C")
MUTED = colors.HexColor("#66717D")
TEAL = colors.HexColor("#138D86")
TEAL_DARK = colors.HexColor("#086A66")
TEAL_PALE = colors.HexColor("#DDEFEA")
AMBER = colors.HexColor("#EDA94B")
AMBER_PALE = colors.HexColor("#F8E8C9")
CORAL = colors.HexColor("#DF6C53")
CORAL_PALE = colors.HexColor("#F6DED7")
CREAM = colors.HexColor("#F3EFE6")
PAPER = colors.HexColor("#FFFDF9")
LINE = colors.HexColor("#D8D2C7")
WHITE = colors.white


def build_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "eyebrow": ParagraphStyle(
            "MemoEyebrow",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.7,
            leading=8,
            textColor=TEAL_DARK,
            spaceAfter=3,
        ),
        "title": ParagraphStyle(
            "MemoTitle",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=25,
            leading=26,
            textColor=NAVY,
            alignment=TA_LEFT,
            spaceAfter=8,
        ),
        "page_title": ParagraphStyle(
            "MemoPageTitle",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=20,
            leading=22,
            textColor=NAVY,
            alignment=TA_LEFT,
            spaceAfter=8,
        ),
        "meta_label": ParagraphStyle(
            "MemoMetaLabel",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.4,
            leading=7.4,
            textColor=MUTED,
        ),
        "meta_value": ParagraphStyle(
            "MemoMetaValue",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=7.5,
            leading=8.8,
            textColor=INK,
        ),
        "status": ParagraphStyle(
            "MemoStatus",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.5,
            leading=7.5,
            textColor=NAVY,
            alignment=TA_CENTER,
        ),
        "callout_label": ParagraphStyle(
            "MemoCalloutLabel",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.6,
            leading=8,
            textColor=AMBER,
            spaceAfter=4,
        ),
        "callout_title": ParagraphStyle(
            "MemoCalloutTitle",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=13.2,
            leading=15.6,
            textColor=WHITE,
            spaceAfter=5,
        ),
        "callout_body": ParagraphStyle(
            "MemoCalloutBody",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8.2,
            leading=10.7,
            textColor=colors.HexColor("#CAD2DA"),
        ),
        "section_label": ParagraphStyle(
            "MemoSectionLabel",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.4,
            leading=7.5,
            textColor=TEAL_DARK,
            spaceAfter=2,
        ),
        "section_title": ParagraphStyle(
            "MemoSectionTitle",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=12.2,
            leading=14,
            textColor=NAVY,
            spaceAfter=6,
        ),
        "body": ParagraphStyle(
            "MemoBody",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.1,
            leading=10.7,
            textColor=INK,
            spaceAfter=5,
        ),
        "body_small": ParagraphStyle(
            "MemoBodySmall",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.2,
            leading=9.2,
            textColor=INK,
            spaceAfter=3,
        ),
        "body_small_muted": ParagraphStyle(
            "MemoBodySmallMuted",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=6.8,
            leading=8.7,
            textColor=MUTED,
            spaceAfter=2,
        ),
        "metric_value": ParagraphStyle(
            "MemoMetricValue",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=15.5,
            leading=17,
            textColor=NAVY,
            alignment=TA_LEFT,
            spaceAfter=3,
        ),
        "metric_label": ParagraphStyle(
            "MemoMetricLabel",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.2,
            leading=7.5,
            textColor=MUTED,
            alignment=TA_LEFT,
        ),
        "panel_title": ParagraphStyle(
            "MemoPanelTitle",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=10.5,
            textColor=NAVY,
            spaceAfter=5,
        ),
        "panel_value": ParagraphStyle(
            "MemoPanelValue",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=16,
            leading=17,
            textColor=TEAL_DARK,
            alignment=TA_CENTER,
            spaceAfter=2,
        ),
        "panel_label": ParagraphStyle(
            "MemoPanelLabel",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=5.9,
            leading=7.2,
            textColor=MUTED,
            alignment=TA_CENTER,
        ),
        "table_header": ParagraphStyle(
            "MemoTableHeader",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.5,
            leading=7.6,
            textColor=WHITE,
        ),
        "table_body": ParagraphStyle(
            "MemoTableBody",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=6.7,
            leading=8.4,
            textColor=INK,
        ),
        "table_body_bold": ParagraphStyle(
            "MemoTableBodyBold",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=6.7,
            leading=8.4,
            textColor=INK,
        ),
        "rule_number": ParagraphStyle(
            "MemoRuleNumber",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8,
            leading=9,
            textColor=WHITE,
            alignment=TA_CENTER,
        ),
        "rule_body": ParagraphStyle(
            "MemoRuleBody",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=7.1,
            leading=9.1,
            textColor=INK,
        ),
        "footer": ParagraphStyle(
            "MemoFooter",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=5.9,
            leading=7,
            textColor=MUTED,
        ),
        "footer_right": ParagraphStyle(
            "MemoFooterRight",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=5.9,
            leading=7,
            textColor=MUTED,
            alignment=TA_RIGHT,
        ),
    }


def p(text: str, style: ParagraphStyle) -> Paragraph:
    if any(ord(character) > 127 for character in text):
        raise ValueError(f"Memo text must remain ASCII: {text!r}")
    return Paragraph(text, style)


def section_header(
    number: str,
    title: str,
    styles: dict[str, ParagraphStyle],
) -> list:
    return [
        p(number.upper(), styles["section_label"]),
        p(title, styles["section_title"]),
    ]


def metric_card(
    value: str,
    label: str,
    background,
    styles: dict[str, ParagraphStyle],
) -> Table:
    card = Table(
        [
            [p(value, styles["metric_value"])],
            [p(label.upper(), styles["metric_label"])],
        ],
        colWidths=[CONTENT_WIDTH / 4 - 3],
    )
    card.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.6, LINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, 0), 8),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 1),
                ("TOPPADDING", (0, 1), (-1, 1), 0),
                ("BOTTOMPADDING", (0, 1), (-1, 1), 8),
            ]
        )
    )
    return card


def stat_card(
    value: str,
    label: str,
    styles: dict[str, ParagraphStyle],
) -> Table:
    card = Table(
        [
            [p(value, styles["panel_value"])],
            [p(label.upper(), styles["panel_label"])],
        ],
        colWidths=[CONTENT_WIDTH / 5 - 1.5],
    )
    card.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PAPER),
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, 0), 5),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 1),
                ("TOPPADDING", (0, 1), (-1, 1), 0),
                ("BOTTOMPADDING", (0, 1), (-1, 1), 4),
            ]
        )
    )
    return card


def styled_table(
    rows: list[list[Paragraph]],
    widths: list[float],
    styles: dict[str, ParagraphStyle],
    *,
    header: bool = True,
    row_backgrounds: bool = True,
    compact: bool = False,
) -> Table:
    table = Table(rows, colWidths=widths, repeatRows=1 if header else 0)
    vertical_padding = 2.5 if compact else 5
    commands = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.45, LINE),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), vertical_padding),
        ("BOTTOMPADDING", (0, 0), (-1, -1), vertical_padding),
    ]
    if header:
        commands.append(("BACKGROUND", (0, 0), (-1, 0), NAVY))
    if row_backgrounds:
        start = 1 if header else 0
        for row_index in range(start, len(rows)):
            if (row_index - start) % 2 == 1:
                commands.append(
                    ("BACKGROUND", (0, row_index), (-1, row_index), CREAM)
                )
    table.setStyle(TableStyle(commands))
    return table


def make_page_one(styles: dict[str, ParagraphStyle]) -> list:
    story: list = [
        p("PRODUCT DECISION MEMO / ECOMMERCE GROWTH", styles["eyebrow"]),
        p("Simplified Checkout Experiment", styles["title"]),
    ]

    meta = Table(
        [
            [
                [
                    p("TO", styles["meta_label"]),
                    p("Ecommerce Product Manager", styles["meta_value"]),
                ],
                [
                    p("FROM", styles["meta_label"]),
                    p("Product Analytics", styles["meta_value"]),
                ],
                [
                    p("DATE", styles["meta_label"]),
                    p("31 July 2026", styles["meta_value"]),
                ],
                p(
                    "PROVISIONAL GO TO EXPERIMENT",
                    styles["status"],
                ),
            ]
        ],
        colWidths=[132, 103, 92, CONTENT_WIDTH - 327],
    )
    meta.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("BACKGROUND", (3, 0), (3, 0), AMBER_PALE),
                ("BOX", (3, 0), (3, 0), 0.7, AMBER),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("LEFTPADDING", (3, 0), (3, 0), 7),
                ("RIGHTPADDING", (3, 0), (3, 0), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    story.extend([meta, Spacer(1, 10)])

    decision = Table(
        [
            [
                [
                    p("DECISION", styles["callout_label"]),
                    p(
                        "Advance a simplified checkout into a user-randomized A/B test.",
                        styles["callout_title"],
                    ),
                    p(
                        "Do not claim that the current checkout causes abandonment. "
                        "Launch only after sticky exposure logging, a validated "
                        "24-hour purchase window, guardrails, current user throughput, "
                        "the planning MDE, and the payment-error margin are approved.",
                        styles["callout_body"],
                    ),
                ]
            ]
        ],
        colWidths=[CONTENT_WIDTH],
    )
    decision.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), NAVY),
                ("LINEBEFORE", (0, 0), (0, -1), 6, CORAL),
                ("LEFTPADDING", (0, 0), (-1, -1), 17),
                ("RIGHTPADDING", (0, 0), (-1, -1), 17),
                ("TOPPADDING", (0, 0), (-1, -1), 13),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 13),
            ]
        )
    )
    story.extend([decision, Spacer(1, 10)])

    metrics = Table(
        [
            [
                metric_card("360,129", "Valid sessions", PAPER, styles),
                metric_card("5,187", "Checkout sessions", TEAL_PALE, styles),
                metric_card("48.02%", "Checkout completion proxy", AMBER_PALE, styles),
                metric_card("$306,678", "Canonical gross revenue", CORAL_PALE, styles),
            ]
        ],
        colWidths=[CONTENT_WIDTH / 4] * 4,
    )
    metrics.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (-1, 0), (-1, -1), 0),
            ]
        )
    )
    story.extend([metrics, Spacer(1, 12)])

    story.extend(section_header("01 / Why this decision", "Observed opportunity and measurement correction", styles))

    observed = [
        p("OBSERVED OPPORTUNITY", styles["section_label"]),
        p(
            "<b>Largest behavioral loss.</b> Product view to cart retains 18.67%; "
            "62,640 sessions are lost before cart.",
            styles["body_small"],
        ),
        p(
            "<b>Checkout is measurable.</b> The governed population contains "
            "5,187 starts and 2,491 clean purchases.",
            styles["body_small"],
        ),
        p(
            "<b>Broader scenario.</b> A +0.50 pp checkout lift equals 25.9 orders "
            "and $1,793, versus 21.46 orders and $1,483.56 for the top single PDP.",
            styles["body_small"],
        ),
        p(
            "<b>No mobile deficit.</b> Mobile purchase conversion is 1.15% versus "
            "1.10% on Desktop; the difference interval includes zero.",
            styles["body_small"],
        ),
    ]
    correction = [
        p("MEASUREMENT CORRECTION", styles["section_label"]),
        p("The 941 strict-path gaps are not 941 abandonments.", styles["panel_title"]),
        p(
            "<b>100%</b> have shipping at or before the governed checkout start.",
            styles["body_small"],
        ),
        p(
            "<b>100%</b> have payment after checkout and before purchase.",
            styles["body_small"],
        ),
        p(
            "<b>0</b> lack shipping everywhere in the session.",
            styles["body_small"],
        ),
        p(
            "<b>92.75%</b> of checkout sessions repeat begin_checkout.",
            styles["body_small"],
        ),
        p(
            "<b>Implication:</b> use a dedicated sticky exposure event and clean "
            "purchase within 24 hours as the primary outcome.",
            styles["body_small"],
        ),
    ]
    evidence = Table(
        [[observed, correction]],
        colWidths=[CONTENT_WIDTH * 0.51, CONTENT_WIDTH * 0.49],
    )
    evidence.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOX", (0, 0), (0, 0), 0.5, LINE),
                ("BOX", (1, 0), (1, 0), 0.5, colors.HexColor("#E4C99E")),
                ("BACKGROUND", (0, 0), (0, 0), PAPER),
                ("BACKGROUND", (1, 0), (1, 0), AMBER_PALE),
                ("LEFTPADDING", (0, 0), (-1, -1), 11),
                ("RIGHTPADDING", (0, 0), (-1, -1), 11),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
            ]
        )
    )
    story.extend([evidence, Spacer(1, 11)])

    story.extend(section_header("02 / Alternatives", "What was considered and why it ranks lower", styles))
    alternatives = [
        [
            p("OPTION", styles["table_header"]),
            p("EVIDENCE", styles["table_header"]),
            p("DECISION", styles["table_header"]),
        ],
        [
            p("<b>Simplify checkout</b>", styles["table_body_bold"]),
            p(
                "+0.50 pp scenario: 25.9 orders and $1,793; direct exposure and "
                "outcome can be instrumented.",
                styles["table_body"],
            ),
            p("<b>Advance to test</b>", styles["table_body_bold"]),
        ],
        [
            p("Optimize top PDP", styles["table_body_bold"]),
            p(
                "Super G Unisex Joggers: 21.46-order scenario; result is robust "
                "in rank but benchmark-sensitive and non-additive.",
                styles["table_body"],
            ),
            p("Retain as secondary", styles["table_body_bold"]),
        ],
        [
            p("Mobile-only redesign", styles["table_body_bold"]),
            p(
                "Mobile purchase conversion is not below Desktop; the 95% "
                "difference interval includes zero.",
                styles["table_body"],
            ),
            p("Deprioritize", styles["table_body_bold"]),
        ],
        [
            p("Channel targeting", styles["table_body_bold"]),
            p(
                "70.13% of sessions sit in weak-quality attribution buckets.",
                styles["table_body"],
            ),
            p("Not decision-grade", styles["table_body_bold"]),
        ],
    ]
    story.append(
        styled_table(
            alternatives,
            [96, 332, CONTENT_WIDTH - 428],
            styles,
        )
    )
    story.extend(
        [
            Spacer(1, 6),
            p(
                "<b>Confidence:</b> sufficient to test, insufficient to ship. "
                "All 43 core and analysis-layer reconciliations passed; historical "
                "segment differences remain descriptive.",
                styles["body_small_muted"],
            ),
        ]
    )
    return story


def make_page_two(styles: dict[str, ParagraphStyle]) -> list:
    story: list = [
        p("PRODUCT DECISION MEMO / IMPLEMENTATION CONTRACT", styles["eyebrow"]),
        p("Experiment contract and launch gates", styles["page_title"]),
        p(
            "The design is reproducible, but the experiment is not launch-ready "
            "until assignment, outcomes, guardrails, and current throughput are "
            "validated at the user level.",
            styles["body"],
        ),
        Spacer(1, 4),
    ]

    story.extend(section_header("03 / Experiment design", "Locked planning rules", styles))
    contract = [
        [
            p("ELEMENT", styles["table_header"]),
            p("LOCKED RULE", styles["table_header"]),
        ],
        [
            p("Control", styles["table_body_bold"]),
            p("Current checkout.", styles["table_body"]),
        ],
        [
            p("Treatment", styles["table_body_bold"]),
            p(
                "One streamlined page combining shipping and payment; remove "
                "nonessential optional fields while preserving price, shipping, "
                "tax, order summary, accessibility, and trust disclosures.",
                styles["table_body"],
            ),
        ],
        [
            p("Randomization", styles["table_body_bold"]),
            p(
                "Sticky 50/50 assignment by pseudonymous user at first eligible "
                "checkout. Repeated checkout starts must not re-randomize.",
                styles["table_body"],
            ),
        ],
        [
            p("Primary outcome", styles["table_body_bold"]),
            p(
                "Clean purchase within 24 hours of first eligible exposure; "
                "intention-to-treat analysis.",
                styles["table_body"],
            ),
        ],
        [
            p("Primary estimand", styles["table_body_bold"]),
            p(
                "Treatment minus Control conversion in percentage points; pooled "
                "z-test and Newcombe interval at each look's boundary.",
                styles["table_body"],
            ),
        ],
        [
            p("Secondary", styles["table_body_bold"]),
            p(
                "Gross purchase revenue per eligible assigned user.",
                styles["table_body"],
            ),
        ],
        [
            p("Guardrails", styles["table_body_bold"]),
            p(
                "Payment-error rate (provisional +1.50 pp non-inferiority margin), "
                "refund or cancellation rate, and completion time.",
                styles["table_body"],
            ),
        ],
    ]
    story.extend(
        [
            styled_table(
                contract,
                [90, CONTENT_WIDTH - 90],
                styles,
                compact=True,
            ),
            Spacer(1, 6),
        ]
    )

    story.extend(section_header("04 / Sample and feasibility", "The guardrail margin, not the MDE, sets the duration", styles))
    sample_cards = Table(
        [
            [
                stat_card("48.02%", "Historical baseline proxy", styles),
                stat_card("+5.00 pp", "Provisional MDE", styles),
                stat_card("6,216", "Max users, 4 looks", styles),
                stat_card("80%", "Ships a true +5 pp lift", styles),
                stat_card("15.8 wk", "Max; 13.4 expected", styles),
            ]
        ],
        colWidths=[CONTENT_WIDTH / 5] * 5,
    )
    sample_cards.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 2),
                ("RIGHTPADDING", (-1, 0), (-1, -1), 0),
            ]
        )
    )
    scenario = Table(
        [
            [
                p("<b>+0.50 pp</b><br/>25.9 orders / $1,793", styles["body_small"]),
                p("<b>+2.00 pp</b><br/>103.7 orders / $7,172", styles["body_small"]),
                p("<b>+5.00 pp</b><br/>259.4 orders / $17,930", styles["body_small"]),
                p(
                    "<b>Important:</b> scenarios are not forecasts. Durations are "
                    "optimistic until current unique-user throughput and the "
                    "24-hour baseline are measured.",
                    styles["body_small"],
                ),
            ]
        ],
        colWidths=[90, 96, 100, CONTENT_WIDTH - 286],
    )
    scenario.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (2, 0), TEAL_PALE),
                ("BACKGROUND", (3, 0), (3, 0), AMBER_PALE),
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, LINE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.extend([sample_cards, Spacer(1, 5), scenario, Spacer(1, 6)])

    story.extend(section_header("05 / Decision rules", "The first rule shipped a true +5 pp lift 29% of the time", styles))
    rules_content = [
        (
            "1",
            "<b>Integrity first.</b> Run the 50/50 sample-ratio-mismatch check at "
            "every look before reading outcomes. Stop if SRM p &lt; 0.001.",
        ),
        (
            "2",
            "<b>Ship on evidence.</b> Ship when the primary z reaches the look's "
            "O'Brien-Fleming boundary (4.05, 2.86, 2.34, 2.02). The point "
            "estimate is not compared with the MDE.",
        ),
        (
            "3",
            "<b>Guardrails.</b> The payment-error upper bound must clear the "
            "+1.50 pp margin at the same confidence; stop for harm if its lower "
            "bound is above zero.",
        ),
        (
            "4",
            "<b>Stopping discipline.</b> Read only at 25, 50, 75, and 100% of "
            "enrollment (daily unadjusted reads: 38% false positives). Stop for "
            "futility at the halfway look if the lift is not positive.",
        ),
    ]
    rule_rows = []
    for number, body in rules_content:
        rule_rows.append(
            [
                p(number, styles["rule_number"]),
                p(body, styles["rule_body"]),
            ]
        )
    rules = Table(rule_rows, colWidths=[24, CONTENT_WIDTH - 24])
    rule_commands = [
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("GRID", (0, 0), (-1, -1), 0.45, LINE),
        ("BACKGROUND", (0, 0), (0, -1), TEAL),
        ("LEFTPADDING", (0, 0), (0, -1), 5),
        ("RIGHTPADDING", (0, 0), (0, -1), 5),
        ("LEFTPADDING", (1, 0), (1, -1), 8),
        ("RIGHTPADDING", (1, 0), (1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 2.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
    ]
    for row_index in range(len(rule_rows)):
        if row_index % 2 == 1:
            rule_commands.append(
                ("BACKGROUND", (1, row_index), (1, row_index), CREAM)
            )
    rules.setStyle(TableStyle(rule_commands))
    story.extend([rules, Spacer(1, 6)])

    story.extend(section_header("06 / Launch gates", "Owners and evidence required before traffic is exposed", styles))
    gates = [
        [
            p("OWNER", styles["table_header"]),
            p("REQUIRED BEFORE LAUNCH", styles["table_header"]),
        ],
        [
            p("Analytics", styles["table_body_bold"]),
            p(
                "Validate sticky exposure, 24-hour clean-purchase attribution, "
                "current unique eligible users per day, the user-level baseline, "
                "and SRM monitoring.",
                styles["table_body"],
            ),
        ],
        [
            p("Engineering", styles["table_body_bold"]),
            p(
                "Prevent re-randomization and validate payment-error, refund or "
                "cancellation, and completion-time telemetry.",
                styles["table_body"],
            ),
        ],
        [
            p("Payments + Product", styles["table_body_bold"]),
            p(
                "Measure the payment-error rate, approve the margin that sets "
                "the duration, and confirm the +5.00 pp MDE.",
                styles["table_body"],
            ),
        ],
        [
            p("Product + Design", styles["table_body_bold"]),
            p(
                "Freeze the treatment and preserve disclosure, accessibility, "
                "price transparency, and user trust.",
                styles["table_body"],
            ),
        ],
    ]
    story.extend(
        [
            styled_table(
                gates,
                [88, CONTENT_WIDTH - 88],
                styles,
                compact=True,
            ),
            Spacer(1, 4),
        ]
    )

    simulation = Table(
        [
            [
                [
                    p("SIMULATION DISCLOSURE", styles["section_label"]),
                    p(
                        "The seeded example (true lift +5.00 pp) estimates +5.08 pp, "
                        "z = 4.01, but misses the payment-error margin, so the rule "
                        "does not ship. It is synthetic demonstration output.",
                        styles["body_small"],
                    ),
                ],
                [
                    p("FINAL RECOMMENDATION", styles["section_label"]),
                    p(
                        "<b>Validate instrumentation and obtain sign-off, then run "
                        "the user-randomized test.</b> Do not ship from historical "
                        "analysis or the seeded simulation.",
                        styles["body_small"],
                    ),
                ],
            ]
        ],
        colWidths=[CONTENT_WIDTH * 0.47, CONTENT_WIDTH * 0.53],
    )
    simulation.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, 0), CORAL_PALE),
                ("BACKGROUND", (1, 0), (1, 0), TEAL_PALE),
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, LINE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    story.extend(
        [
            simulation,
            Spacer(1, 2),
            p(
                "Evidence base: Google GA4 public ecommerce sample, 2020-11-01 "
                "through 2021-01-31; aggregate run 20260731T052813Z; 43 of 43 hard "
                "checks passed. <link href='https://ga4-product-growth-decision-dashboard.world8866.chatgpt.site' "
                "color='#086A66'><u>Open the public interactive dashboard</u></link>.",
                styles["body_small_muted"],
            ),
        ]
    )
    return story


def draw_page(canvas, document) -> None:
    canvas.saveState()
    canvas.setTitle("Product Decision Memo - Simplified Checkout Experiment")
    canvas.setAuthor("Product Analytics")
    canvas.setSubject(
        "Evidence-based product decision and A/B test launch contract"
    )

    canvas.setFillColor(NAVY)
    canvas.rect(0, PAGE_HEIGHT - 7, PAGE_WIDTH, 7, stroke=0, fill=1)
    canvas.setFillColor(TEAL)
    canvas.rect(0, PAGE_HEIGHT - 7, PAGE_WIDTH * 0.34, 7, stroke=0, fill=1)

    footer_y = 22
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.5)
    canvas.line(LEFT_MARGIN, footer_y + 9, PAGE_WIDTH - RIGHT_MARGIN, footer_y + 9)

    canvas.setFont("Helvetica", 5.8)
    canvas.setFillColor(MUTED)
    canvas.drawString(
        LEFT_MARGIN,
        footer_y,
        "Product Growth Analytics | Observed evidence, scenarios, and simulation are labeled separately",
    )
    canvas.setFont("Helvetica-Bold", 5.8)
    canvas.drawRightString(
        PAGE_WIDTH - RIGHT_MARGIN,
        footer_y,
        f"PAGE {document.page} OF 2",
    )
    canvas.restoreState()


def build_pdf() -> None:
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    styles = build_styles()

    document = SimpleDocTemplate(
        str(TEMP_PDF),
        pagesize=letter,
        leftMargin=LEFT_MARGIN,
        rightMargin=RIGHT_MARGIN,
        topMargin=TOP_MARGIN,
        bottomMargin=BOTTOM_MARGIN,
        title="Product Decision Memo - Simplified Checkout Experiment",
        author="Product Analytics",
        subject="Ecommerce product decision and experiment design",
    )

    story = [
        *make_page_one(styles),
        PageBreak(),
        *make_page_two(styles),
    ]
    document.build(story, onFirstPage=draw_page, onLaterPages=draw_page)

    reader = PdfReader(str(TEMP_PDF))
    if len(reader.pages) != 2:
        raise RuntimeError(
            f"Decision memo must be exactly two pages; found {len(reader.pages)}."
        )

    page_text = [page.extract_text() or "" for page in reader.pages]
    normalized_text = [" ".join(text.split()) for text in page_text]
    required_phrases = [
        "Advance a simplified checkout",
        "The 941 strict-path gaps are not 941 abandonments",
        "Experiment contract and launch gates",
        "SIMULATION DISCLOSURE",
        "Do not ship from historical analysis",
        "Open the public interactive dashboard",
    ]
    missing = [
        phrase
        for phrase in required_phrases
        if not any(phrase in text for text in normalized_text)
    ]
    if missing:
        raise RuntimeError(
            "Generated memo is missing required text: "
            + ", ".join(missing)
        )

    for page_number, text in enumerate(normalized_text, start=1):
        footer = f"PAGE {page_number} OF 2"
        if footer not in text:
            raise RuntimeError(f"Generated memo is missing footer: {footer}")

    dashboard_url = (
        "https://ga4-product-growth-decision-dashboard.world8866.chatgpt.site"
    )
    annotation_urls: list[str] = []
    for page in reader.pages:
        for annotation_ref in page.get("/Annots", []):
            annotation = annotation_ref.get_object()
            action = annotation.get("/A")
            if action and action.get("/URI"):
                annotation_urls.append(action.get("/URI"))
    if dashboard_url not in annotation_urls:
        raise RuntimeError("Generated memo is missing the dashboard hyperlink.")

    shutil.copy2(TEMP_PDF, OUTPUT_PDF)
    print(f"Created {OUTPUT_PDF.relative_to(ROOT)}")
    print("Validated: 2 pages, required text, footers, and dashboard link")


if __name__ == "__main__":
    build_pdf()
