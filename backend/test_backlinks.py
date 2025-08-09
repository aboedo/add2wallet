#!/usr/bin/env python3
"""
Test script for Apple Wallet pass backlinks functionality.

This script tests the associatedStoreIdentifiers feature that creates
backlinks from Apple Wallet passes to the Add2Wallet app.

Usage:
    python test_backlinks.py
    
    # With custom App Store ID
    APP_STORE_ID=1234567890 python test_backlinks.py
"""

import os
import sys
import json
import tempfile
import zipfile
from typing import Dict, Any

# Add the app directory to the path so we can import our modules
sys.path.append(os.path.join(os.path.dirname(__file__), 'app'))

try:
    from app.services.pass_generator import PassGenerator
except ImportError:
    print("❌ Failed to import PassGenerator. Make sure you're running from the backend directory.")
    sys.exit(1)


def test_associated_store_identifiers():
    """Test the _get_associated_store_identifiers method."""
    print("🧪 Testing _get_associated_store_identifiers method...")
    
    pg = PassGenerator()
    
    # Test without APP_STORE_ID
    old_app_store_id = os.environ.get('APP_STORE_ID')
    if 'APP_STORE_ID' in os.environ:
        del os.environ['APP_STORE_ID']
    
    store_ids = pg._get_associated_store_identifiers()
    print(f"   Without APP_STORE_ID: {store_ids}")
    assert store_ids is None, "Should return None when APP_STORE_ID is not set"
    
    # Test with valid APP_STORE_ID
    os.environ['APP_STORE_ID'] = '1234567890'
    store_ids = pg._get_associated_store_identifiers()
    print(f"   With APP_STORE_ID=1234567890: {store_ids}")
    assert store_ids == [1234567890], f"Expected [1234567890], got {store_ids}"
    
    # Test with invalid APP_STORE_ID
    os.environ['APP_STORE_ID'] = 'invalid'
    store_ids = pg._get_associated_store_identifiers()
    print(f"   With invalid APP_STORE_ID: {store_ids}")
    assert store_ids is None, "Should return None for invalid APP_STORE_ID"
    
    # Restore original value
    if old_app_store_id:
        os.environ['APP_STORE_ID'] = old_app_store_id
    elif 'APP_STORE_ID' in os.environ:
        del os.environ['APP_STORE_ID']
    
    print("   ✅ _get_associated_store_identifiers tests passed")


def test_basic_pass_with_backlinks():
    """Test creating a basic pass with backlinks."""
    print("🧪 Testing basic pass creation with backlinks...")
    
    # Set a test App Store ID
    os.environ['APP_STORE_ID'] = '1234567890'
    
    pg = PassGenerator()
    
    # Create a basic pass
    pass_data = pg.create_basic_pass(
        title='Test Pass with Backlinks',
        description='Testing associatedStoreIdentifiers field',
        organization='Test Organization'
    )
    
    print(f"   Created pass with {len(pass_data)} bytes")
    assert len(pass_data) > 0, "Pass data should not be empty"
    
    # Extract and verify the pass.json contains associatedStoreIdentifiers
    with tempfile.NamedTemporaryFile(suffix='.pkpass') as temp_file:
        temp_file.write(pass_data)
        temp_file.flush()
        
        with zipfile.ZipFile(temp_file.name, 'r') as zf:
            with zf.open('pass.json') as pass_file:
                pass_json = json.loads(pass_file.read().decode('utf-8'))
    
    print(f"   Pass JSON keys: {list(pass_json.keys())}")
    assert 'associatedStoreIdentifiers' in pass_json, "Pass should contain associatedStoreIdentifiers"
    assert pass_json['associatedStoreIdentifiers'] == [1234567890], f"Expected [1234567890], got {pass_json['associatedStoreIdentifiers']}"
    
    print("   ✅ Basic pass with backlinks test passed")


def test_enhanced_pass_with_backlinks():
    """Test creating an enhanced pass with backlinks."""
    print("🧪 Testing enhanced pass creation with backlinks...")
    
    # Set a test App Store ID
    os.environ['APP_STORE_ID'] = '987654321'
    
    pg = PassGenerator()
    
    # Create sample pass info
    pass_info = {
        'title': 'Concert Ticket',
        'event_name': 'Test Concert',
        'date': '2024-12-25',
        'time': '7:00 PM',
        'venue_name': 'Test Venue',
        'event_type': 'concert'
    }
    
    # Create an enhanced pass
    pass_data = pg.create_enhanced_pass(
        title='Enhanced Test Pass',
        description='Testing enhanced pass with backlinks',
        pass_info=pass_info,
        bg_color='rgb(255,45,85)',
        fg_color='rgb(255,255,255)',
        label_color='rgb(255,255,255)'
    )
    
    print(f"   Created enhanced pass with {len(pass_data)} bytes")
    assert len(pass_data) > 0, "Pass data should not be empty"
    
    # Extract and verify the pass.json contains associatedStoreIdentifiers
    with tempfile.NamedTemporaryFile(suffix='.pkpass') as temp_file:
        temp_file.write(pass_data)
        temp_file.flush()
        
        with zipfile.ZipFile(temp_file.name, 'r') as zf:
            with zf.open('pass.json') as pass_file:
                pass_json = json.loads(pass_file.read().decode('utf-8'))
    
    print(f"   Pass JSON keys: {list(pass_json.keys())}")
    assert 'associatedStoreIdentifiers' in pass_json, "Enhanced pass should contain associatedStoreIdentifiers"
    assert pass_json['associatedStoreIdentifiers'] == [987654321], f"Expected [987654321], got {pass_json['associatedStoreIdentifiers']}"
    
    print("   ✅ Enhanced pass with backlinks test passed")


def test_pass_without_backlinks():
    """Test creating a pass without backlinks when APP_STORE_ID is not set."""
    print("🧪 Testing pass creation without backlinks...")
    
    # Remove APP_STORE_ID
    if 'APP_STORE_ID' in os.environ:
        del os.environ['APP_STORE_ID']
    
    pg = PassGenerator()
    
    # Create a basic pass
    pass_data = pg.create_basic_pass(
        title='Test Pass without Backlinks',
        description='Testing pass without associatedStoreIdentifiers'
    )
    
    print(f"   Created pass with {len(pass_data)} bytes")
    assert len(pass_data) > 0, "Pass data should not be empty"
    
    # Extract and verify the pass.json does NOT contain associatedStoreIdentifiers
    with tempfile.NamedTemporaryFile(suffix='.pkpass') as temp_file:
        temp_file.write(pass_data)
        temp_file.flush()
        
        with zipfile.ZipFile(temp_file.name, 'r') as zf:
            with zf.open('pass.json') as pass_file:
                pass_json = json.loads(pass_file.read().decode('utf-8'))
    
    print(f"   Pass JSON keys: {list(pass_json.keys())}")
    assert 'associatedStoreIdentifiers' not in pass_json, "Pass should NOT contain associatedStoreIdentifiers when APP_STORE_ID is not set"
    
    print("   ✅ Pass without backlinks test passed")


def main():
    """Run all backlinks tests."""
    print("🚀 Starting Apple Wallet backlinks tests...\n")
    
    try:
        test_associated_store_identifiers()
        print()
        
        test_basic_pass_with_backlinks()
        print()
        
        test_enhanced_pass_with_backlinks()
        print()
        
        test_pass_without_backlinks()
        print()
        
        print("🎉 All backlinks tests passed successfully!")
        print("\n📝 Summary:")
        print("   - associatedStoreIdentifiers field is correctly added when APP_STORE_ID is set")
        print("   - Field is omitted when APP_STORE_ID is not configured")
        print("   - Both basic and enhanced passes support backlinks")
        print("   - Invalid APP_STORE_ID values are handled gracefully")
        
        # Show current configuration
        current_app_store_id = os.environ.get('APP_STORE_ID')
        if current_app_store_id:
            print(f"\n🔧 Current APP_STORE_ID: {current_app_store_id}")
        else:
            print("\n🔧 APP_STORE_ID not currently set")
            print("   Set it with: export APP_STORE_ID=your_itunes_store_id")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()