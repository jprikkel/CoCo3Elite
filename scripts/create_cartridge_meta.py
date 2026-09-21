#!/usr/bin/env python3
"""Build 184x138 4-bpp BMP previews and per-cartridge metadata sidecars."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from PIL import Image


GAME_LIST_SOURCE = "https://www.lcurtisboyle.com/nitros9/coco_game_list.html"
CATALOG_SOURCE = "https://en.wikipedia.org/wiki/List_of_TRS-80_Color_Computer_games"


RECORDS = [
    dict(file="Androne (1983) (26-3096) (Tandy).ccc", title="Androne", description="Explore a 3D maze, battle monsters, find the generator, and escape.", players="1", joystick="true", keyboard="false", left="false", developer="Robert Arnstein", publisher="Tandy", year="1983", result="pass", source="https://www.lcurtisboyle.com/nitros9/androne.html"),
    dict(file="Downland v1.1 (1983) (26-3046) (Tandy).ccc", title="Downland v1.1", description="Collect keys and navigate ten hazardous interconnected cave chambers.", players="1", joystick="true", keyboard="false", left="false", developer="Michael Aichlmayr", publisher="Tandy through Spectral Associates", year="1983", result="fail", source="https://www.lcurtisboyle.com/nitros9/downland.html"),
    dict(file="Music (1980) (26-3151) (Tandy).ccc", title="Music", description="Use the Color Computer keyboard to play notes and explore music.", players="1", joystick="false", keyboard="true", left="false", developer="Tandy", publisher="Tandy", year="1980", result="pass", source="https://en.wikipedia.org/wiki/List_of_software_for_the_TRS-80"),
    dict(file="Reactoid (1983) (26-3092) (Tandy) (1).ccc", title="Reactoid", description="Deflect reactor particles toward energy posts and prevent a meltdown.", players="1", joystick="true", keyboard="false", left="true", developer="Robert Arnstein; original design by Mark Siegel", publisher="Tandy", year="1983", result="intermittent", source="https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Reactoid%20%28Tandy%29.pdf"),
    dict(file="Reactoid (1983) (26-3092) (Tandy).ccc", title="Reactoid", description="Deflect reactor particles toward energy posts and prevent a meltdown.", players="1", joystick="true", keyboard="false", left="true", developer="Robert Arnstein; original design by Mark Siegel", publisher="Tandy", year="1983", result="intermittent", source="https://colorcomputerarchive.com/repo/Documents/Manuals/Games/Reactoid%20%28Tandy%29.pdf"),
    dict(file="Temple of ROM (1984) (26-3045) (Tandy).ccc", title="Temple of ROM", description="Explore a scrolling temple maze while collecting treasure and fighting monsters.", players="1-2", joystick="true", keyboard="false", left="false", developer="Rick Adams", publisher="Tandy", year="1984", result="pass", source="https://templeofrom.com/"),
    dict(file="Mega-Bug (1982) (26-3076) (Tandy).ccc", title="Mega-Bug", description="Clear a huge maze while evading monsters through a moving magnifier.", players="1", joystick="true", keyboard="false", left="false", developer="Steve Bjork", publisher="Tandy", year="1982", result="pass", source="https://www.lcurtisboyle.com/nitros9/megabug.html"),
    dict(file="Galactic Attack (1982) (26-3066) (Tandy).ccc", title="Galactic Attack", description="Defend against diving alien formations in a Galaxian-style space shooter.", players="1", joystick="true", keyboard="false", left="false", developer="Lou Haehn and The Image Producers", publisher="Tandy", year="1982", result="pass", source=CATALOG_SOURCE),
    dict(file="Dungeons of Daggorath (Shield Fix) (Aaron Oliver).ccc", title="Dungeons of Daggorath - Shield Fix", description="Explore a real-time first-person dungeon using concise typed commands.", players="1", joystick="false", keyboard="true", left="false", developer="DynaMicro; shield fix by Aaron Oliver", publisher="Tandy", year="1982", result="pass", source="https://www.cocopedia.com/wiki/index.php/Dungeons_of_Daggorath"),
    dict(file="Dungeons of Daggorath (1982) (26-3093) (Tandy).ccc", title="Dungeons of Daggorath", description="Explore a real-time first-person dungeon using concise typed commands.", players="1", joystick="false", keyboard="true", left="false", developer="DynaMicro", publisher="Tandy", year="1982", result="pass", source="https://www.cocopedia.com/wiki/index.php/Dungeons_of_Daggorath"),
    dict(file="Dino Wars (1981) (26-3057) (Tandy).ccc", title="Dino Wars", description="Two dinosaurs battle each other in a head-to-head fighting game.", players="2", joystick="true", keyboard="false", left="true", developer="Robert Kilgus", publisher="Tandy", year="1981", result="pass", source=CATALOG_SOURCE),
    dict(file="Diagnostics v2.0 (1982) (26-3019) (Tandy) (1).ccc", title="Color Computer Diagnostics v2.0", description="Exercise Color Computer memory, ROM, keyboard, video, and peripherals.", players="1", joystick="true", keyboard="true", left="false", developer="Tandy", publisher="Tandy", year="1982", result="pass", source="https://colorcomputerarchive.com/coco/Documents/Manuals/Applications/Diagnostics%20%28Tandy%29.pdf"),
    dict(file="Diagnostics (1980) (26-3019) (Tandy).ccc", title="Color Computer Diagnostics", description="Exercise Color Computer memory, ROM, keyboard, video, and peripherals.", players="1", joystick="true", keyboard="true", left="false", developer="Tandy", publisher="Tandy", year="1980", result="pass", source="https://colorcomputerarchive.com/coco/Documents/Manuals/Applications/Diagnostics%20%28Tandy%29.pdf"),
    dict(file="Downland v1.0 (1983) (26-3046) (Tandy).ccc", title="Downland v1.0", description="Collect keys and navigate ten hazardous interconnected cave chambers.", players="1", joystick="true", keyboard="false", left="false", developer="Michael Aichlmayr", publisher="Tandy through Spectral Associates", year="1983", result="pass", source="https://www.lcurtisboyle.com/nitros9/downland.html"),
    dict(file="Skiing (1981) (26-3058) (Tandy).ccc", title="Skiing", description="Guide a downhill skier through gates while racing for a fast time.", players="1", joystick="true", keyboard="false", left="false", developer="Tandy", publisher="Tandy", year="1981", result="pass", source=CATALOG_SOURCE),
    dict(file="ZIADIAG.CCC", title="ZIADIAG", description="Community diagnostic cartridge for checking CoCo hardware and system ROMs.", players="1", joystick="true", keyboard="true", left="false", developer="CoCo community", publisher="CoCo community", year="unknown", result="pass", source="https://colorcomputerarchive.com/"),
    dict(file="Bustout (1981) (26-3056) (Tandy).ccc", title="Bustout", description="Break a wall of bricks by keeping a bouncing ball in play.", players="1", joystick="true", keyboard="false", left="false", developer="Tandy", publisher="Tandy", year="1981", result="pass", source=CATALOG_SOURCE),
    dict(file="Stellar Lifeline (1983) (26-3047) (Tandy).ccc", title="Stellar Lifeline", description="Protect a space convoy from asteroids, mines, and alien attackers.", players="1", joystick="true", keyboard="false", left="false", developer="Steve Bjork and SRB Software", publisher="Tandy", year="1983", result="fail", source=CATALOG_SOURCE),
    dict(file="Starblaze (1983) (26-3094) (Tandy).ccc", title="Star Blaze", description="Patrol 64 sectors while managing shields, fuel, and ammunition.", players="1", joystick="true", keyboard="false", left="false", developer="Greg Zumwalt", publisher="Tandy", year="1983", result="pass", source="https://www.mobygames.com/game/175017/star-blaze/"),
    dict(file="Spidercide (1983) (26-3049) (Tandy).ccc", title="Spidercide", description="Defend the playfield from waves of hostile spiders.", players="1", joystick="true", keyboard="false", left="false", developer="Tim Swisher", publisher="Tandy", year="1983", result="pass", source=CATALOG_SOURCE),
    dict(file="Spectaculator (1983) (26-3104) (Tandy).ccc", title="Spectaculator", description="Create and calculate spreadsheet-style tables on the Color Computer.", players="1", joystick="false", keyboard="true", left="false", developer="Tandy", publisher="Tandy", year="1983", result="fail", source="https://www.trs-80.com/sub-publications-manuals-software-3.htm"),
    dict(file="Slay the Nereis (1983) (26-3086) (Tandy).ccc", title="Slay the Nereis", description="Fight an underwater invasion in a Centipede-inspired arcade game.", players="1", joystick="true", keyboard="false", left="false", developer="John J. and Margaret S. Fiedler", publisher="Tandy", year="1983", result="pass", source=CATALOG_SOURCE),
    dict(file="SDS80C (1981) (The Micro Works).ccc", title="SDS80C", description="Integrated 6809 editor, assembler, and machine-language monitor.", players="1", joystick="false", keyboard="true", left="false", developer="Andrew Phelps", publisher="The Micro Works", year="1981", result="pass", source="https://colorcomputerarchive.com/coco/Documents/Manuals/Programming/Software%20Development%20System%20SDS80C%20Owner%27s%20Manual%20%28The%20Micro%20Works%29.pdf"),
    dict(file="Roman Checkers (1981) (26-3071) (Tandy).ccc", title="Roman Checkers", description="Play an Othello-style strategy game presented with an ancient Rome theme.", players="1-2", joystick="true", keyboard="false", left="false", developer="The Image Producers", publisher="Tandy", year="1981", result="fail", source=CATALOG_SOURCE),
    dict(file="Panic Button (1983) (26-3147) (Tandy).ccc", title="Panic Button", description="Arcade action adapted from the First Star Software game.", players="1", joystick="true", keyboard="false", left="false", developer="Paul Kanevsky and First Star Software", publisher="Tandy", year="1983", result="fail", source=CATALOG_SOURCE),
    dict(file="Gomoku-Renju (1983) (26-3069) (Tandy).ccc", title="Gomoku-Renju", description="Play the five-in-a-row board game against the computer.", players="1", joystick="false", keyboard="true", left="false", developer="Intelligent Software", publisher="Tandy", year="1983", result="pass", source=CATALOG_SOURCE),
    dict(file="Fraction Fever (1984) (26-3169) (Spinnaker).ccc", title="Fraction Fever", description="Move a pogo stick to the platform showing an equivalent fraction.", players="1", joystick="true", keyboard="false", left="false", developer="Tom Snyder Productions", publisher="Spinnaker Software", year="1984", result="fail", source="https://colorcomputerarchive.com/coco/Documents/Manuals/Educational/Fraction%20Fever%20%28Spinnaker%29.pdf"),
    dict(file="Direct Connect Modem Pak (1985) (26-2228) (Tandy).ccc", title="Direct Connect Modem Pak", description="Terminal firmware for Tandy's 300-baud direct-connect modem cartridge.", players="1", joystick="false", keyboard="true", left="false", developer="Tandy", publisher="Tandy", year="1985", result="pass", source="https://colorcomputerarchive.com/coco/Documents/Manuals/Hardware/Direct%20Connect%20Modem%20Pak%20%28Tandy%29.pdf"),
    dict(file="Demolition Derby (1984) (26-3044) (Tandy).ccc", title="Demolition Derby", description="Crash rival cars across sixteen arenas while keeping your car running.", players="1", joystick="true", keyboard="false", left="false", developer="John Gabbard and Spectral Associates", publisher="Tandy", year="1984", result="pass", source=CATALOG_SOURCE),
    dict(file="Color Baseball (1980) (26-3095) (Tandy).ccc", title="Color Baseball", description="One- or two-player baseball with pitching, batting, fielding, and bunting.", players="1-2", joystick="true", keyboard="false", left="true", developer="Dale Lear", publisher="Tandy", year="1982", result="fail", source="https://www.lcurtisboyle.com/nitros9/colorbaseball.html"),
    dict(file="Coco Tuner (Real Time Specialties).ccc", title="CoCo Tuner", description="Tune and analyze musical pitch using the Color Computer display.", players="1", joystick="false", keyboard="true", left="false", developer="Real Time Specialties", publisher="Real Time Specialties", year="unknown", result="pass", source="https://colorcomputerarchive.com/"),
]


def write_bmp4(image: Image.Image, output: Path) -> None:
    """Write the restricted 184x138, 16-color, uncompressed BMP profile."""
    width, height = 184, 138
    source = image.convert("RGB")
    # Serial captures contain the centered 512x384 CoCo display inside a
    # 640x480 HDMI frame. Remove that ten-percent border on every side before
    # scaling so the browser preview emphasizes the game rather than overscan.
    crop_x = source.width // 10
    crop_y = source.height // 10
    source = source.crop(
        (crop_x, crop_y, source.width - crop_x, source.height - crop_y)
    ).resize((width, height), Image.Resampling.LANCZOS)
    indexed = source.quantize(
        colors=16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
    )

    palette_data = indexed.getpalette() or []
    palette = []
    for index in range(16):
        base = index * 3
        rgb = tuple(palette_data[base : base + 3])
        palette.append(rgb if len(rgb) == 3 else (0, 0, 0))

    packed_width = (width + 1) // 2
    stride = (packed_width + 3) & ~3
    pixels = bytearray()
    values = list(indexed.get_flattened_data())
    for y in range(height - 1, -1, -1):
        row = values[y * width : (y + 1) * width]
        encoded = bytearray((row[x] << 4) | row[x + 1] for x in range(0, width, 2))
        encoded.extend(b"\0" * (stride - len(encoded)))
        pixels.extend(encoded)

    pixel_offset = 14 + 40 + 16 * 4
    file_size = pixel_offset + len(pixels)
    file_header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, pixel_offset)
    info_header = struct.pack(
        "<IiiHHIIiiII", 40, width, height, 1, 4, 0, len(pixels), 2835, 2835, 16, 16
    )
    color_table = b"".join(struct.pack("<BBBB", b, g, r, 0) for r, g, b in palette)
    output.write_bytes(file_header + info_header + color_table + pixels)


def write_metadata(record: dict[str, str], output: Path) -> None:
    keys = (
        "title",
        "description",
        "players",
        "joystick",
        "keyboard",
        "player1_left_joystick",
        "developer",
        "publisher",
        "year",
        "verified",
        "test_result",
        "source",
    )
    values = dict(record)
    values["player1_left_joystick"] = values.pop("left")
    values["verified"] = "true"
    values["test_result"] = values.pop("result")
    output.write_text(
        "".join(f"{key}={values[key]}\n" for key in keys), encoding="ascii"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--captures", type=Path, default=Path("build/test-output/cartridge-results")
    )
    parser.add_argument("--output", type=Path, default=Path("roms/.meta"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    for record in RECORDS:
        cartridge = Path(record["file"])
        stem = cartridge.stem
        capture = args.captures / f"{stem}.png"
        if not capture.is_file():
            raise FileNotFoundError(f"Missing capture for {record['file']}: {capture}")
        with Image.open(capture) as image:
            write_bmp4(image, args.output / f"{stem}.bmp")
        write_metadata(record, args.output / f"{stem}.meta")
        print(f"created {stem}.bmp and {stem}.meta")


if __name__ == "__main__":
    main()
