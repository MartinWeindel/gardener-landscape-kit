# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

FROM alpine:3.23

# Install openssh and git
RUN apk add --no-cache openssh git && \
    adduser -D -h /home/git -s /bin/false git && \
    mkdir -p /home/git/.ssh /srv/git && \
    chown -R git:git /home/git /srv/git && \
    chmod 700 /home/git/.ssh

# Configure git-shell for git user
RUN apk add --no-cache shadow && \
    echo "$(command -v git-shell)" >> /etc/shells && \
    chsh -s "$(command -v git-shell)" git && \
    echo 'git:*' | chpasswd -e

# SSHD config: no password login, no PTY/shell for git user
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config && \
    echo "AllowUsers git" >> /etc/ssh/sshd_config && \
    echo "Subsystem sftp internal-sftp" >> /etc/ssh/sshd_config

# Provide host keys at first start if missing
RUN ssh-keygen -A

# Copy init script (creates initial bare repo if requested)
COPY init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

# Authorized keys will be mounted to /authorized_keys, then synced to /home/git/.ssh/authorized_keys by init.sh
CMD ["/usr/local/bin/init.sh"]
