# Oracle sidecar: docker CLI (talks to the mounted host socket) + python stdlib.
# No daemon here — it drives the host daemon to run the arvo vul/fix images.
FROM docker:cli

RUN apk add --no-cache python3

COPY server.py /opt/server.py

EXPOSE 8000
CMD ["python3", "/opt/server.py"]
