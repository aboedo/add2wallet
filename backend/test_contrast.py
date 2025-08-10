#!/usr/bin/env python3
"""Test contrast adjustment logic with various background colors."""

import sys
sys.path.append('.')

from app.services.pass_generator import PassGenerator

def test_contrast():
    """Test contrast adjustment with various background colors."""
    
    test_colors = [
        ("rgb(255,255,255)", "Pure white"),
        ("rgb(240,240,240)", "Light gray"),
        ("rgb(255,255,0)", "Yellow"),
        ("rgb(124,196,125)", "Light green (Eiffel)"),
        ("rgb(173,216,230)", "Light blue"),
        ("rgb(255,192,203)", "Pink"),
        ("rgb(128,128,128)", "Medium gray"),
        ("rgb(100,100,100)", "Dark gray"),
        ("rgb(0,0,255)", "Blue"),
        ("rgb(255,0,0)", "Red"),
        ("rgb(0,128,0)", "Green"),
        ("rgb(128,0,128)", "Purple"),
        ("rgb(0,0,0)", "Pure black"),
    ]
    
    pass_gen = PassGenerator()
    
    print("="*80)
    print("CONTRAST ADJUSTMENT TEST RESULTS")
    print("="*80)
    print()
    
    for bg_color, description in test_colors:
        print(f"\n🎨 Testing: {description}")
        print(f"   Input background: {bg_color}")
        
        # Test with default white text
        bg_adj, fg_adj, label_adj = pass_gen._ensure_color_contrast(
            bg_color, "rgb(255,255,255)", "rgb(255,255,255)"
        )
        
        print(f"   Output foreground: {fg_adj}")
        print(f"   Output label: {label_adj}")
        print("-" * 40)

if __name__ == '__main__':
    test_contrast()