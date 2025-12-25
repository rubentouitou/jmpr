# syntax=docker/dockerfile:1
FROM frappe/bench:latest

SHELL ["/bin/bash", "-c"]

WORKDIR /workspace
COPY . /workspace

# Ensure init script is executable inside the image
RUN chmod +x docker/init.sh

ENV SHELL=/bin/bash

CMD ["bash", "/workspace/docker/init.sh"]
