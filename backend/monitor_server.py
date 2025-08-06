#!/usr/bin/env python3
"""Server monitoring script that shows real-time logs and status."""

import subprocess
import sys
import time
import signal
from datetime import datetime

class ServerMonitor:
    def __init__(self):
        self.server_process = None
        
    def start_server(self):
        """Start the server and monitor its output."""
        print("🚀 Starting Add2Wallet Backend Server...")
        print("=" * 60)
        
        try:
            # Start the server process
            self.server_process = subprocess.Popen(
                [sys.executable, "run.py"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )
            
            # Monitor the output in real-time
            while True:
                output = self.server_process.stdout.readline()
                if output == '' and self.server_process.poll() is not None:
                    break
                if output:
                    timestamp = datetime.now().strftime("%H:%M:%S")
                    print(f"[{timestamp}] {output.strip()}")
                    
        except KeyboardInterrupt:
            print("\n🛑 Shutting down server...")
            self.stop_server()
        except Exception as e:
            print(f"❌ Error starting server: {e}")
            
    def stop_server(self):
        """Stop the server process."""
        if self.server_process:
            self.server_process.terminate()
            self.server_process.wait()
            print("✅ Server stopped successfully")
            
    def signal_handler(self, signum, frame):
        """Handle interrupt signals."""
        self.stop_server()
        sys.exit(0)

if __name__ == "__main__":
    monitor = ServerMonitor()
    
    # Handle Ctrl+C gracefully
    signal.signal(signal.SIGINT, monitor.signal_handler)
    signal.signal(signal.SIGTERM, monitor.signal_handler)
    
    print("📱 iPhone App Configuration:")
    print("   Server URL: http://192.168.68.66:8000")
    print("   API Documentation: http://192.168.68.66:8000/docs")
    print("=" * 60)
    
    monitor.start_server()