# syntax=docker/dockerfile:1
FROM frappe/bench:latest

SHELL ["/bin/bash", "-c"]

WORKDIR /workspace
COPY . /workspace

# Ensure init script exists at /workspace/init.sh regardless of build context
RUN if [ -f docker/init.sh ]; then cp docker/init.sh ./init.sh; fi && \
    chmod +x ./init.sh

ENV SHELL=/bin/bash

CMD ["bash", "/workspace/init.sh"]
