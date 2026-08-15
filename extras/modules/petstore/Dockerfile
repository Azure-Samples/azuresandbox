# Adds Application Insights observability to the stock Petstore image using the
# standalone Application Insights Java agent (auto-instrumentation). No changes to
# the application source code are required - the agent is attached to the JVM via
# JAVA_TOOL_OPTIONS.
#
# This Dockerfile is built and pushed to the network-isolated Azure Container
# Registry by the vm-jumpbox-linux host (jumplinux1) - see
# scripts/build-petstore-image.sh. Both build arguments are supplied by Terraform.

ARG SOURCE_IMAGE=swaggerapi/petstore31:latest
FROM ${SOURCE_IMAGE}

# The Application Insights Java agent is published as a versioned GitHub release
# asset. Note: the unversioned '.../releases/latest/download/...' URL does NOT
# resolve to the jar (it returns an HTML 404 page), so the version must be pinned.
ARG APPINSIGHTS_VERSION=3.7.9
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/${APPINSIGHTS_VERSION}/applicationinsights-agent-${APPINSIGHTS_VERSION}.jar /agent/applicationinsights-agent.jar

# Attach the agent to the JVM for every process started in the container.
ENV JAVA_TOOL_OPTIONS="-javaagent:/agent/applicationinsights-agent.jar"
