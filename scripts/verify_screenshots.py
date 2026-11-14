#!/usr/bin/env python3
"""
verify_screenshots.py - Automated visual quality gate for WarframeWatch iOS CI
Uses only Pillow (PIL) to ensure compatibility across all environments.
Pure ASCII output to avoid terminal encoding issues.
"""

import sys
import os
import math
from PIL import Image

# These screens are expected to show a populated local weapon catalogue and
# calculator.  A large block of the app's error-red text therefore means that
# a resource-loading failure reached the user, even if the process did not
# crash and the page otherwise has normal brightness/variance.
CALCULATOR_DATA_SCREENS = {
    "screen_arsenal.png",
    "screen_arsenal_melee.png",
    "screen_arsenal_config.png",
    "screen_arsenal_companion_config.png",
    "screen_calc.png",
    "screen_calc_companion.png",
    "screen_calc_result.png",
}


def missing_calculator_data_error_pixels(img):
    """Count the error-red glyph pixels used by the unavailable-data state."""
    return sum(
        1
        for r, g, b in img.getdata()
        if r >= 210 and g <= 160 and b <= 160 and r - g >= 60 and r - b >= 60
    )

def verify_screenshot(img_path):
    print("==========================================")
    print(f"=== Verifying Screenshot: {os.path.basename(img_path)} ===")
    print("==========================================")
    
    if not os.path.exists(img_path):
        print(f"[FAIL] Screenshot file not found: {img_path}")
        return False
        
    img = Image.open(img_path).convert('RGB')
    width, height = img.size
    print(f"[INFO] Resolution: {width} x {height}")
    
    # 1. Dimension Check
    if width < 375 or height < 667:
        print(f"[FAIL] Resolution suspiciously small: {width}x{height}")
        return False
        
    aspect_ratio = height / width
    print(f"[INFO] Aspect Ratio: {aspect_ratio:.3f}")
    if aspect_ratio < 1.7:
        print(f"[FAIL] Aspect ratio {aspect_ratio:.2f} does not match modern iPhone (expected >= 1.78)")
        return False

    # 2. Letterbox Analysis (Check top-left status bar and bottom home bar)
    # Sample top-left corner (x: 20 to 100, y: 10 to 40)
    top_pixels = []
    for y in range(10, min(50, height // 20)):
        for x in range(20, min(120, width // 4)):
            top_pixels.append(img.getpixel((x, y)))
            
    max_top_val = max(max(p) for p in top_pixels) if top_pixels else 0
    print(f"[CHECK] Top-left status area max pixel brightness: {max_top_val}")
    
    # Sample bottom area (bottom 25 pixels)
    bottom_pixels = []
    for y in range(height - 25, height):
        for x in range(width // 4, 3 * width // 4):
            bottom_pixels.append(img.getpixel((x, y)))
            
    max_bottom_val = max(max(p) for p in bottom_pixels) if bottom_pixels else 0
    print(f"[CHECK] Bottom home bar area max pixel brightness: {max_bottom_val}")
    
    # If the app is letterboxed with black bars, max_top_val and max_bottom_val will be 0.
    if max_top_val == 0 and max_bottom_val == 0:
        print("[FAIL] CRITICAL: App appears LETTERBOXED with dead black bars at top and bottom!")
        return False
        
    # 3. Content Area Brightness & Variance (y: 15% to 80%)
    content_samples = []
    gold_count = 0
    cyan_count = 0
    step = 5
    for y in range(int(height * 0.15), int(height * 0.80), step):
        for x in range(int(width * 0.05), int(width * 0.95), step):
            r, g, b = img.getpixel((x, y))
            brightness = 0.299 * r + 0.587 * g + 0.114 * b
            content_samples.append(brightness)
            
            # Gold detection (Warframe theme gold: r > 150, g > 130, b < 120)
            if r > 150 and g > 130 and b < 120:
                gold_count += 1
            # Cyan/Lotus detection (r < 120, g > 140, b > 140)
            elif r < 120 and g > 140 and b > 140:
                cyan_count += 1
                
    n = len(content_samples)
    mean_val = sum(content_samples) / n
    variance = sum((x - mean_val) ** 2 for x in content_samples) / n
    std_dev = math.sqrt(variance)
    
    print(f"[DATA] Content Mean Brightness: {mean_val:.2f} (0-255)")
    print(f"[DATA] Content Std Deviation: {std_dev:.2f}")
    print(f"[DATA] Theme Gold Pixels Sampled: {gold_count}")
    print(f"[DATA] Theme Cyan Pixels Sampled: {cyan_count}")
    
    if std_dev < 4.0:
        print("[FAIL] Content area has virtually zero variance (solid blank screen or crash)!")
        return False

    # The former gate accepted the fully rendered-but-useless resource error
    # page.  Only apply this semantic check to arsenal/calculator captures:
    # red is a valid colour for unrelated alerts elsewhere in the app.
    if os.path.basename(img_path) in CALCULATOR_DATA_SCREENS:
        error_pixels = missing_calculator_data_error_pixels(img)
        max_error_pixels = max(250, int(width * height * 0.0005))
        print(f"[CHECK] Calculator unavailable-data error-red pixels: {error_pixels} (max {max_error_pixels})")
        if error_pixels > max_error_pixels:
            print("[FAIL] Calculator screen shows the unavailable-data error state, not usable weapon/calculation content!")
            return False
        
    print(f"[PASS] {os.path.basename(img_path)} verified successfully.")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python verify_screenshots.py <path_to_image>")
        sys.exit(1)
        
    all_passed = True
    for path in sys.argv[1:]:
        if not verify_screenshot(path):
            all_passed = False
            
    if not all_passed:
        print("\n[FAIL] Visual validation failed! Workflow halted.")
        sys.exit(1)
    else:
        print("\n[SUCCESS] Visual quality gate PASSED!")
        sys.exit(0)
