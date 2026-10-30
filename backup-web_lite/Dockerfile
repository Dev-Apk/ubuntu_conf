FROM alpine:3.19
RUN apk add --no-cache python3
WORKDIR /app
COPY backup.py .
CMD ["python3", "backup.py"]
