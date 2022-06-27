FROM alpine:3.13 as builder

# Install build dependencies
RUN set -eux \
	&& apk --no-cache add \
		curl \
		git \
		unzip

# Get Terraform
ARG TF_VERSION=latest
RUN set -eux \
	&& if [ "${TF_VERSION}" = "latest" ]; then \
		VERSION="$( curl -sS https://releases.hashicorp.com/terraform/ \
			| tac | tac \
			| grep -Eo '/terraform/[.0-9]+\"' \
			| grep -Eo '[.0-9]+' \
			| sort -V \
			| tail -1 )"; \
	else \
		VERSION="$( curl -sS https://releases.hashicorp.com/terraform/ \
			| tac | tac \
			| grep -Eo "/terraform/${TF_VERSION}\.[.0-9]+\"" \
			| grep -Eo '[.0-9]+' \
			| sort -V \
			| tail -1 )"; \
	fi \
	&& curl -sS -L -O \
		https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip \
	&& unzip terraform_${VERSION}_linux_amd64.zip \
	&& mv terraform /usr/bin/terraform \
	&& chmod +x /usr/bin/terraform

# Get Terragrunt
ARG TG_VERSION=latest
RUN set -eux \
	&& git clone https://github.com/gruntwork-io/terragrunt /terragrunt \
	&& cd /terragrunt \
	&& if [ "${TG_VERSION}" = "latest" ]; then \
		VERSION="$( git describe --abbrev=0 --tags )"; \
	else \
		VERSION="$( git tag | grep -E "v${TG_VERSION}\.[.0-9]+" | sort -Vu | tail -1 )" ;\
	fi \
	&& curl -sS -L \
		https://github.com/gruntwork-io/terragrunt/releases/download/${VERSION}/terragrunt_linux_amd64 \
		-o /usr/bin/terragrunt \
	&& chmod +x /usr/bin/terragrunt

# Test binaries
RUN set -eux \
	&& terraform --version \
	&& terragrunt --version


# Use a clean tiny image to store artifacts in
FROM alpine:3.13

ARG HELM_VERSION=3.2.1
ARG KUBECTL_VERSION=1.17.5
ARG KUSTOMIZE_VERSION=v3.8.1
ARG KUBESEAL_VERSION=v0.15.0
ARG ANSIBLE_VERSION_ARG=2.10.16


# Labels.
LABEL maintainer="will@willhallonline.co.uk" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.name="willhallonline/ansible" \
    org.label-schema.description="Ansible inside Docker" \
    org.label-schema.url="https://github.com/willhallonline/docker-ansible" \
    org.label-schema.vcs-url="https://github.com/willhallonline/docker-ansible" \
    org.label-schema.vendor="Will Hall Online" \
    org.label-schema.docker.cmd="docker run --rm -it -v $(pwd):/ansible -v ~/.ssh/id_rsa:/root/id_rsa willhallonline/ansible:2.10-alpine-3.12"



LABEL \
	maintainer="Chokkalingam K <chokkalingam.k@outlook.com>" 
RUN set -eux \
	&& apk add --no-cache git openssh-client

#add Terraform and Terragrunt
COPY --from=builder /usr/bin/terraform /usr/bin/terraform
COPY --from=builder /usr/bin/terragrunt /usr/bin/terragrunt
COPY data/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 777 /docker-entrypoint.sh


# RUN apk add --no-cache \
#         python3 \
#         py3-pip \
#     && pip3 install --upgrade pip \
#     && pip3 install --no-cache-dir \
#         awscli \
#     && rm -rf /var/cache/apk/*

ENV BASE_URL="https://get.helm.sh"
ENV TAR_FILE="helm-v${HELM_VERSION}-linux-amd64.tar.gz"
RUN apk add --update --no-cache curl ca-certificates bash git && \
    curl -sL ${BASE_URL}/${TAR_FILE} | tar -xvz && \
    mv linux-amd64/helm /usr/bin/helm && \
    chmod +x /usr/bin/helm && \
    rm -rf linux-amd64

# add helm-diff
RUN helm plugin install https://github.com/databus23/helm-diff && rm -rf /tmp/helm-*

# add helm-unittest
RUN helm plugin install https://github.com/quintush/helm-unittest && rm -rf /tmp/helm-*

# add helm-push
RUN helm plugin install https://github.com/chartmuseum/helm-push && rm -rf /tmp/helm-*

# Install kubectl (same version of aws esk)
RUN curl -sLO https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
    mv kubectl /usr/bin/kubectl && \
    chmod +x /usr/bin/kubectl

# Install kustomize (latest release)
RUN curl -sLO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
    tar xvzf kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
    mv kustomize /usr/bin/kustomize && \
    chmod +x /usr/bin/kustomize

# Install eksctl (latest version)
RUN curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && \
    mv /tmp/eksctl /usr/bin && \
    chmod +x /usr/bin/eksctl

# Install awscli
RUN apk add --update --no-cache python3 && \
    python3 -m ensurepip && \
    pip3 install --upgrade pip && \
    pip3 install awscli && \
    pip3 cache purge

# https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
# Install aws-iam-authenticator
RUN authenticator=$(aws --no-sign-request s3 ls s3://amazon-eks --recursive |grep aws-iam-authenticator$|grep amd64 |awk '{print $NF}' |sort -V|tail -1) && \
    aws --no-sign-request s3 cp s3://amazon-eks/${authenticator} /usr/bin/aws-iam-authenticator && \
    chmod +x /usr/bin/aws-iam-authenticator

# # Install jq
# RUN apk add --update --no-cache jq

# # Install for envsubst
# RUN apk add --update --no-cache gettext

# # Install kubeseal
# RUN curl -sL https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-linux-amd64 -o kubeseal && \
#     mv kubeseal /usr/bin/kubeseal && \
#     chmod +x /usr/bin/kubeseal

# Install ansible 
ENV ANSIBLE_VERSION ${ANSIBLE_VERSION_ARG}
RUN apk --no-cache add \
        sudo \
        python3\
        py3-pip \
        openssl \
        ca-certificates \
        sshpass \
        openssh-client \
        rsync \
        git && \
    apk --no-cache add --virtual build-dependencies \
        python3-dev \
        libffi-dev \
        musl-dev \
        gcc \
        cargo \
        openssl-dev \
        libressl-dev \
        build-base && \
    pip3 install --upgrade pip cffi wheel && \
    pip3 install ansible-base==${ANSIBLE_VERSION} && \
    pip3 install mitogen ansible-lint jmespath && \
    pip3 install --upgrade pywinrm && \
    apk del build-dependencies && \
    rm -rf /var/cache/apk/* && \
    rm -rf /root/.cache/pip && \
    rm -rf /root/.cargo

RUN	mkdir -p /etc/ansible && \
    echo 'localhost' > /etc/ansible/hosts


WORKDIR /data
#RUN aws --version   # Just to make sure its installed alright
CMD ["terragrunt", "--version"]
ENTRYPOINT ["/docker-entrypoint.sh"]