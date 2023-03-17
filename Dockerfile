# Container image that runs your code
FROM alpine:3.17

# git, bash, curl
RUN apk add --no-cache git bash curl tree sed make jq openssh

# Install golang
COPY --from=golang:1.19-alpine /usr/local/go/ /usr/local/go/
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/gobin"
ENV PATH="${GOPATH}/bin:${PATH}"

RUN git clone https://github.com/minamijoyo/hcledit /hcledit
WORKDIR /hcledit
RUN cat Makefile
RUN make install
RUN ls -al /gobin/bin
RUN hcledit version
WORKDIR /


# tfenv
RUN git clone --depth=1 https://github.com/tfutils/tfenv.git /tfenv
ENV PATH="${PATH}:/tfenv/bin"
RUN tfenv install 1.3.9
RUN tfenv use 1.3.9

#App 
COPY main.sh /main.sh

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
