import math
from PIL import Image, ImageDraw, ImageFont

def create_ui_mockup():
    width = 800
    height = 1680

    # Colors (from AppTheme)
    bg_color = (0, 0, 0)
    card_bg = (18, 18, 18)
    card_variant = (28, 28, 28)
    border_color = (44, 44, 44)
    text_primary = (244, 244, 245)
    text_secondary = (212, 212, 216)
    text_muted = (161, 161, 170)
    accent_green = (0, 230, 118)
    charging_cyan = (0, 229, 255)
    amber = (255, 179, 0)
    crimson = (255, 23, 68)

    img = Image.new("RGBA", (width, height), bg_color)
    draw = ImageDraw.Draw(img)

    # Fonts
    bold_font_path = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
    regular_font_path = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
    mono_font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

    font_huge = ImageFont.truetype(bold_font_path, 56)
    font_large_bold = ImageFont.truetype(bold_font_path, 26)
    font_title = ImageFont.truetype(bold_font_path, 20)
    font_sub_bold = ImageFont.truetype(bold_font_path, 15)
    font_body = ImageFont.truetype(regular_font_path, 14)
    font_small_bold = ImageFont.truetype(bold_font_path, 12)
    font_small = ImageFont.truetype(regular_font_path, 12)
    font_tiny_mono = ImageFont.truetype(mono_font_path, 11)
    font_tiny_bold = ImageFont.truetype(bold_font_path, 10)

    # 1. Android Status Bar
    draw.text((36, 18), "09:41", fill=text_primary, font=font_sub_bold)
    # Status bar icons on right
    draw.text((680, 18), "5G", fill=text_primary, font=font_small_bold)
    # Battery icon outline
    draw.rounded_rectangle([720, 20, 755, 34], radius=3, outline=text_primary, width=2)
    draw.rectangle([755, 24, 758, 30], fill=text_primary)
    draw.rectangle([723, 23, 749, 31], fill=accent_green) # 84% fill

    # 2. Top AppBar
    y_appbar = 60
    # Green pulse dot
    draw.ellipse([36, y_appbar + 8, 48, y_appbar + 20], fill=accent_green)
    draw.text((60, y_appbar + 3), "PowerWarden", fill=text_primary, font=font_large_bold)

    # Top right actions
    # Theme toggle circle
    draw.ellipse([670, y_appbar + 2, 702, y_appbar + 34], fill=card_variant, outline=border_color)
    draw.ellipse([680, y_appbar + 12, 692, y_appbar + 24], fill=text_secondary)
    # Refresh circle
    draw.ellipse([720, y_appbar + 2, 752, y_appbar + 34], fill=card_variant, outline=border_color)
    draw.text((731, y_appbar + 9), "↻", fill=text_secondary, font=font_title)

    # 3. Inline Privilege Banner
    y_banner = 118
    draw.rounded_rectangle([32, y_banner, 768, y_banner + 72], radius=16, fill=(35, 25, 0), outline=amber, width=1)
    # Shield badge
    draw.ellipse([48, y_banner + 16, 88, y_banner + 56], fill=(60, 45, 0))
    draw.text((60, y_banner + 24), "🛡", fill=amber, font=font_sub_bold)
    draw.text((102, y_banner + 14), "Baseline Sensor Mode Active", fill=text_primary, font=font_sub_bold)
    draw.text((102, y_banner + 36), "Link Shizuku or Wireless ADB for thread inspection & 1-tap kill.", fill=text_secondary, font=font_small)
    # Pair button
    draw.rounded_rectangle([680, y_banner + 18, 752, y_banner + 54], radius=8, fill=amber)
    draw.text((700, y_banner + 26), "PAIR", fill=(0, 0, 0), font=font_small_bold)

    # 4. Hero Command Card
    y_hero = 206
    draw.rounded_rectangle([32, y_hero, 768, y_hero + 224], radius=22, fill=card_bg, outline=border_color, width=1)

    # Upper row: 84% + -410 mA + NOMINAL
    draw.text((56, y_hero + 22), "84%", fill=text_primary, font=font_huge)
    draw.text((210, y_hero + 42), "-410 mA", fill=accent_green, font=font_large_bold)
    # Status pill [NOMINAL]
    draw.rounded_rectangle([360, y_hero + 46, 452, y_hero + 74], radius=6, fill=(0, 40, 15), outline=accent_green, width=1)
    draw.text((376, y_hero + 52), "NOMINAL", fill=accent_green, font=font_small_bold)

    # Human-readable subtitle
    draw.text((56, y_hero + 96), "🔋  Battery Healthy · ~17.5h remaining (~9.1%/hr)", fill=text_muted, font=font_body)

    # Divider
    draw.line([32, y_hero + 135, 768, y_hero + 135], fill=border_color, width=1)

    # Lower 4-metric ribbon
    ribbon_y = y_hero + 148
    items = [
        ("CURRENT", "-410 mA", accent_green),
        ("POWER", "1.7W", amber),
        ("TEMP", "34.2°C", accent_green),
        ("VOLTS", "4.12V", text_secondary)
    ]
    col_width = (768 - 32) / 4
    for i, (label, val, col) in enumerate(items):
        cx = 32 + i * col_width
        draw.text((cx + 25, ribbon_y), label, fill=text_muted, font=font_tiny_bold)
        draw.text((cx + 25, ribbon_y + 24), val, fill=col, font=font_sub_bold)
        if i < 3:
            draw.line([cx + col_width, ribbon_y + 4, cx + col_width, ribbon_y + 54], fill=border_color, width=1)

    # 5. Discharge Timeline Chart
    y_chart = 446
    draw.rounded_rectangle([32, y_chart, 768, y_chart + 260], radius=18, fill=card_bg, outline=border_color, width=1)
    draw.text((52, y_chart + 18), "DISCHARGE TIMELINE", fill=text_muted, font=font_small_bold)
    draw.ellipse([640, y_chart + 22, 648, y_chart + 30], fill=charging_cyan)
    draw.text((656, y_chart + 18), "Flow Rate (mA)", fill=text_muted, font=font_small)

    # Chart grid lines
    for gy in range(y_chart + 65, y_chart + 215, 45):
        draw.line([60, gy, 740, gy], fill=(35, 35, 35), width=1)

    # Curve points
    curve_points = []
    num_pts = 45
    for i in range(num_pts):
        px = 60 + (i / (num_pts - 1)) * 680
        # Realistic wave
        sine = math.sin(i * 0.45) * 28 + math.cos(i * 0.9) * 15
        py = (y_chart + 140) + sine
        curve_points.append((px, py))

    # Gradient fill under curve
    poly_points = [(60, y_chart + 215)] + curve_points + [(740, y_chart + 215)]
    draw.polygon(poly_points, fill=(0, 45, 55, 120))
    # Line stroke
    for i in range(len(curve_points) - 1):
        draw.line([curve_points[i], curve_points[i+1]], fill=charging_cyan, width=3)

    # Scrubbing tooltip
    tip_x, tip_y = curve_points[28]
    draw.ellipse([tip_x - 5, tip_y - 5, tip_x + 5, tip_y + 5], fill=charging_cyan, outline=(255, 255, 255), width=2)
    # Tooltip box
    box_w, box_h = 220, 46
    draw.rounded_rectangle([tip_x - box_w // 2, tip_y - 60, tip_x + box_w // 2, tip_y - 14], radius=10, fill=card_variant, outline=border_color, width=1)
    draw.text((tip_x - 85, tip_y - 54), "410 mA (84%)", fill=text_primary, font=font_small_bold)
    draw.text((tip_x - 85, tip_y - 36), "34.2°C • Screen On", fill=charging_cyan, font=font_small)

    # X axis labels
    draw.text((60, y_chart + 228), "-60m", fill=text_muted, font=font_tiny_mono)
    draw.text((380, y_chart + 228), "-30m", fill=text_muted, font=font_tiny_mono)
    draw.text((710, y_chart + 228), "Now", fill=text_primary, font=font_tiny_mono)

    # 6. Active App Energy Consumption Section
    y_apps = 722
    draw.text((36, y_apps), "ACTIVE APP ENERGY CONSUMPTION", fill=text_muted, font=font_small_bold)
    draw.text((708, y_apps), "Refresh", fill=charging_cyan, font=font_small_bold)

    # App 1: Instagram (CRITICAL)
    y_card1 = y_apps + 24
    draw.rounded_rectangle([32, y_card1, 768, y_card1 + 104], radius=16, fill=(35, 10, 15), outline=crimson, width=1)
    # App icon
    draw.ellipse([50, y_card1 + 18, 92, y_card1 + 60], fill=(60, 20, 25))
    draw.text((64, y_card1 + 26), "⚡", fill=crimson, font=font_title)
    draw.text((106, y_card1 + 18), "Instagram", fill=text_primary, font=font_title)
    draw.text((106, y_card1 + 42), "com.instagram.android", fill=text_muted, font=font_tiny_mono)

    # Action buttons: CRITICAL chip + STOP button
    draw.rounded_rectangle([590, y_card1 + 20, 672, y_card1 + 50], radius=8, fill=(60, 15, 20), outline=crimson, width=1)
    draw.text((604, y_card1 + 27), "CRITICAL", fill=crimson, font=font_small_bold)
    draw.rounded_rectangle([684, y_card1 + 18, 748, y_card1 + 52], radius=8, fill=crimson)
    draw.text((702, y_card1 + 26), "STOP", fill=(255, 255, 255), font=font_small_bold)

    # Metrics pill
    draw.rounded_rectangle([106, y_card1 + 66, 200, y_card1 + 92], radius=6, fill=card_variant)
    draw.text((118, y_card1 + 71), "~225 mA", fill=charging_cyan, font=font_small_bold)
    draw.text((214, y_card1 + 71), "28.5% CPU", fill=crimson, font=font_small_bold)
    draw.text((305, y_card1 + 71), "•  380MB RAM", fill=text_muted, font=font_small)

    # App 2: Spotify (CALM)
    y_card2 = y_card1 + 116
    draw.rounded_rectangle([32, y_card2, 768, y_card2 + 104], radius=16, fill=card_bg, outline=border_color, width=1)
    draw.ellipse([50, y_card2 + 18, 92, y_card2 + 60], fill=card_variant)
    draw.text((64, y_card2 + 26), "♫", fill=accent_green, font=font_title)
    draw.text((106, y_card2 + 18), "Spotify", fill=text_primary, font=font_title)
    draw.text((106, y_card2 + 42), "com.spotify.music", fill=text_muted, font=font_tiny_mono)

    # Action buttons: CALM chip + STOP button
    draw.rounded_rectangle([606, y_card2 + 20, 672, y_card2 + 50], radius=8, fill=(10, 40, 20), outline=accent_green, width=1)
    draw.text((624, y_card2 + 27), "CALM", fill=accent_green, font=font_small_bold)
    draw.rounded_rectangle([684, y_card2 + 18, 748, y_card2 + 52], radius=8, fill=card_variant, outline=border_color, width=1)
    draw.text((702, y_card2 + 26), "STOP", fill=text_muted, font=font_small_bold)

    # Metrics pill
    draw.rounded_rectangle([106, y_card2 + 66, 190, y_card2 + 92], radius=6, fill=card_variant)
    draw.text((118, y_card2 + 71), "~38 mA", fill=charging_cyan, font=font_small_bold)
    draw.text((205, y_card2 + 71), "3.8% CPU", fill=text_secondary, font=font_small_bold)
    draw.text((285, y_card2 + 71), "•  165MB RAM", fill=text_muted, font=font_small)

    # App 3: Google Play Services (Background Sync)
    y_card3 = y_card2 + 116
    draw.rounded_rectangle([32, y_card3, 768, y_card3 + 104], radius=16, fill=(35, 25, 0), outline=amber, width=1)
    draw.ellipse([50, y_card3 + 18, 92, y_card3 + 60], fill=(50, 35, 0))
    draw.text((64, y_card3 + 26), "⚙", fill=amber, font=font_title)
    draw.text((106, y_card3 + 18), "Google Play Services", fill=text_primary, font=font_title)
    draw.text((106, y_card3 + 42), "com.google.android.gms", fill=text_muted, font=font_tiny_mono)

    draw.rounded_rectangle([600, y_card3 + 20, 672, y_card3 + 50], radius=8, fill=(40, 30, 0), outline=amber, width=1)
    draw.text((615, y_card3 + 27), "HEAVY", fill=amber, font=font_small_bold)
    draw.rounded_rectangle([684, y_card3 + 18, 748, y_card3 + 52], radius=8, fill=card_variant, outline=border_color, width=1)
    draw.text((702, y_card3 + 26), "STOP", fill=text_muted, font=font_small_bold)

    draw.rounded_rectangle([106, y_card3 + 66, 195, y_card3 + 92], radius=6, fill=card_variant)
    draw.text((118, y_card3 + 71), "~95 mA", fill=charging_cyan, font=font_small_bold)
    draw.text((210, y_card3 + 71), "12.4% CPU", fill=amber, font=font_small_bold)
    draw.text((300, y_card3 + 71), "•  240MB RAM", fill=text_muted, font=font_small)

    # 7. Material 3 Bottom NavigationBar
    y_nav = height - 90
    draw.line([0, y_nav, width, y_nav], fill=border_color, width=1)
    draw.rectangle([0, y_nav + 1, width, height], fill=bg_color)

    # Tab 1: Sentinel (Active with emerald pill)
    draw.rounded_rectangle([90, y_nav + 12, 175, y_nav + 46], radius=18, fill=(0, 45, 20))
    draw.text((122, y_nav + 18), "🛡", fill=accent_green, font=font_sub_bold)
    draw.text((105, y_nav + 54), "Sentinel", fill=accent_green, font=font_small_bold)

    # Tab 2: History
    draw.text((388, y_nav + 18), "⏱", fill=text_muted, font=font_sub_bold)
    draw.text((375, y_nav + 54), "History", fill=text_muted, font=font_small_bold)

    # Tab 3: Engine
    draw.text((650, y_nav + 18), "⚙", fill=text_muted, font=font_sub_bold)
    draw.text((642, y_nav + 54), "Engine", fill=text_muted, font=font_small_bold)

    # Output path
    output_path = "/root/power-warden/docs/assets/powerwarden_dashboard_mockup.png"
    img.save(output_path, "PNG", quality=100)
    print(f"Mockup successfully created at: {output_path}")

create_ui_mockup()
