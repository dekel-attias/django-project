from http.server import BaseHTTPRequestHandler, HTTPServer
import boto3
import uuid
import json
import logging
from datetime import datetime
from typing import Optional

# Configuration
TABLE_NAME = "user_messages"
REGION = "eu-central-1"
HOST = '0.0.0.0'
PORT = 8080

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create DynamoDB client
dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

class EchoHandler(BaseHTTPRequestHandler):
    def _send_response(self, status_code: int, message: str) -> None:
        """Helper method to send HTTP responses."""
        self.send_response(status_code)
        self.end_headers()
        self.wfile.write(message.encode())

    def _save_message(self, body: str) -> Optional[str]:
        """Save message to DynamoDB and return message ID."""
        message_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        
        try:
            table.put_item(Item={
                "message_id": message_id,
                "body": body,
                "timestamp": timestamp
            })
            logger.info(f"Message saved with ID: {message_id}")
            return message_id
        except Exception as e:
            logger.error(f"Failed to save message: {e}")
            return None

    def do_GET(self):
        """Handle GET requests."""
        logger.info("GET request received")
        self._send_response(200, "Hello from GET")

    def do_POST(self):
        """Handle POST requests."""
        logger.info("POST request received")
        
        # Read request body
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length == 0:
            self._send_response(400, "No content provided")
            return
            
        body = self.rfile.read(content_length).decode("utf-8")
        
        # Save to DynamoDB
        message_id = self._save_message(body)
        if message_id is None:
            self._send_response(500, "Error saving to DynamoDB")
            return
        
        # Return success response
        response = f"Message received and stored with ID {message_id}"
        self._send_response(200, response)

def main():
    """Start the HTTP server."""
    server = HTTPServer((HOST, PORT), EchoHandler)
    logger.info(f"Server starting on {HOST}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server shutting down...")
        server.shutdown()

if __name__ == '__main__':
    main()
