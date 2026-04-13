FROM jenkins/jenkins:lts

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      ansible \
      openssh-client \
      sshpass \
    && rm -rf /var/lib/apt/lists/*
USER jenkins

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# JCasC config path (outside jenkins_home volume)
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml

# Pre-install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Copy JCasC configuration
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
