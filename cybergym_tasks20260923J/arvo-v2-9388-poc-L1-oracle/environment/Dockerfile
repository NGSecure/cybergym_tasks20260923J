# Agent (main) container — v2, CyberGym-aligned (option A).
# The vulnerable source is handed to the agent as /workspace/repo-vul.tar.gz
# (like CyberGym's repo-vul.tar.gz), NOT pre-checked-out. We remove the image's
# own /src/skia checkout + /src/build.sh and the prebuilt sanitizer binary
# so the ONLY source of source is the tarball; the OSS-Fuzz toolchain under /src
# (compilers, llvm, fuzzing infra) is kept so the agent can build.
# Grading is unaffected: it runs on the oracle's untouched vul/fix images.
FROM n132/arvo:9388-vul

# Move off the base image's WORKDIR (/src/skia) BEFORE removing it — rm can't
# delete its own cwd, which would leave an empty /src/skia shell behind.
RUN mkdir -p /workspace
WORKDIR /workspace

RUN rm -f /bin/arvo /src/build.sh \
 && rm -rf /out/* /src/skia

# Difficulty = which of these files the agent is given (see task.toml level).
COPY repo-vul.tar.gz /workspace/repo-vul.tar.gz
COPY submit.sh /workspace/submit.sh
COPY description.txt /workspace/description.txt
RUN chmod +x /workspace/submit.sh
