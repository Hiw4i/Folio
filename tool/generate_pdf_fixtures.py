"""Generate the small, deterministic PDF corpus used by reader tests."""

from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw
from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "test" / "fixtures" / "pdf"
TEMP = ROOT / "tmp" / "pdfs"


def make_searchable_long() -> None:
    target = OUTPUT / "searchable_long.pdf"
    pdf = canvas.Canvas(str(target), pagesize=A4, pageCompression=1)
    width, height = A4
    for page in range(1, 25):
        pdf.setFont("Helvetica-Bold", 18)
        pdf.drawString(54, height - 62, f"Folio PDF fixture - page {page}")
        pdf.setFont("Helvetica", 11)
        for line in range(22):
            suffix = " Searchable phrase." if line in (3, 17) else ""
            pdf.drawString(
                54,
                height - 98 - line * 28,
                f"Line {line + 1}: stable layout and lazy rendering check.{suffix}",
            )
        pdf.setFont("Helvetica", 9)
        pdf.drawCentredString(width / 2, 28, f"{page} / 24")
        pdf.showPage()
    pdf.save()


def make_rotated() -> None:
    source = TEMP / "rotated_source.pdf"
    pdf = canvas.Canvas(str(source), pagesize=landscape(A4), pageCompression=1)
    pdf.setFont("Helvetica-Bold", 22)
    pdf.drawString(64, 520, "Rotated page fixture")
    pdf.setFont("Helvetica", 12)
    pdf.drawString(64, 486, "Rotation and page geometry must remain readable.")
    pdf.save()

    reader = PdfReader(str(source))
    writer = PdfWriter()
    writer.add_page(reader.pages[0].rotate(90))
    with (OUTPUT / "rotated.pdf").open("wb") as stream:
        writer.write(stream)


def make_image_only() -> None:
    image = Image.new("RGB", (900, 1200), "#f5f2e9")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((70, 80, 830, 1120), radius=42, fill="#ddd7c5")
    draw.rectangle((120, 180, 780, 500), fill="#282b30")
    draw.text((150, 550), "RASTER ONLY - NO PDF TEXT LAYER", fill="#17191c")
    encoded = BytesIO()
    image.save(encoded, format="JPEG", quality=78, optimize=True)
    encoded.seek(0)

    target = OUTPUT / "image_only.pdf"
    pdf = canvas.Canvas(str(target), pagesize=A4, pageCompression=1)
    width, height = A4
    pdf.drawImage(
        ImageReader(encoded),
        36,
        36,
        width=width - 72,
        height=height - 72,
        preserveAspectRatio=True,
        anchor="c",
    )
    pdf.save()


def make_encrypted() -> None:
    source = TEMP / "encrypted_source.pdf"
    pdf = canvas.Canvas(str(source), pagesize=A4, pageCompression=1)
    pdf.setFont("Helvetica-Bold", 20)
    pdf.drawString(54, 770, "Password-protected fixture")
    pdf.save()

    reader = PdfReader(str(source))
    writer = PdfWriter()
    writer.append_pages_from_reader(reader)
    writer.encrypt("folio-test")
    with (OUTPUT / "encrypted.pdf").open("wb") as stream:
        writer.write(stream)


def make_malformed() -> None:
    (OUTPUT / "malformed.pdf").write_bytes(
        b"%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n"
        b"2 0 obj << /Type /Pages /Count 99 /Kids ["
    )


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    TEMP.mkdir(parents=True, exist_ok=True)
    make_searchable_long()
    make_rotated()
    make_image_only()
    make_encrypted()
    make_malformed()
    for item in TEMP.iterdir():
        if item.is_file():
            item.unlink()
    TEMP.rmdir()


if __name__ == "__main__":
    main()
