# Use a lightweight official Python image as the base
FROM python:3.9-slim

# Set the working directory inside the container
WORKDIR /app

# Install boto3
RUN pip install boto3

# Copy the Python application code into the container
COPY main.py .

# Expose the port that the app runs on
EXPOSE 8080

# Define the command to run the application when the container starts
CMD ["python", "main.py"]
