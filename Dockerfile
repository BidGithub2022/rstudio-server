# Use a RHEL base image
FROM registry.access.redhat.com/ubi9/ubi:latest

# Install build dependencies including Fortran compiler
RUN dnf -y install dnf-plugins-core && \
    dnf -y install wget sudo openssl openssl-devel \
    gcc gcc-c++ gcc-gfortran make bzip2 perl-core \
    zlib-devel bzip2-devel xz-devel pcre2-devel \
    libcurl-devel \
    java-17-openjdk-devel && \
    dnf clean all

# Set environment variables
ENV R_VERSION=4.4.3
ENV R_HOME=/usr/local/lib/R
ENV PATH="/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib"

# Download and install R from source with minimal configuration
RUN wget https://cran.r-project.org/src/base/R-4/R-${R_VERSION}.tar.gz && \
    tar -xf R-${R_VERSION}.tar.gz && \
    cd R-${R_VERSION} && \
    ./configure \
        --prefix=/usr/local \
        --enable-R-shlib \
        --enable-memory-profiling \
        --with-blas=no \
        --with-lapack=no \
        --without-x \
        --without-recommended-packages \
        --without-readline \
        FC=gfortran \
        F77=gfortran && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf R-${R_VERSION}* && \
    echo "R installation completed"

# Verify R installation
RUN R --version

# Download and install RStudio Server with error checking
RUN set -e && \
    RSTUDIO_RPM="rstudio-server-rhel-2024.12.1-563-x86_64.rpm" && \
    echo "Downloading RStudio Server..." && \
    wget --no-verbose https://download2.rstudio.org/server/rhel9/x86_64/${RSTUDIO_RPM} && \
    echo "Verifying download..." && \
    if [ -f "${RSTUDIO_RPM}" ]; then \
        echo "Installing RStudio Server..." && \
        dnf -y install ./${RSTUDIO_RPM} && \
        rm -f ${RSTUDIO_RPM} && \
        echo "RStudio Server installation completed"; \
    else \
        echo "Failed to download RStudio Server" && \
        exit 1; \
    fi

# Create R library directory and set permissions
RUN mkdir -p /usr/local/lib/R/library && \
    chmod -R 777 /usr/local/lib/R/library

# Create a user for RStudio
RUN useradd -m -s /bin/bash rstudio && \
    echo "rstudio:rstudio" | chpasswd && \
    echo "rstudio ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R rstudio:rstudio /usr/local/lib/R/library

# Create required directories
RUN mkdir -p /var/run/rstudio-server && \
    mkdir -p /var/lib/rstudio-server && \
    mkdir -p /var/lock/rstudio-server && \
    chown -R rstudio:rstudio /var/run/rstudio-server \
        /var/lib/rstudio-server \
        /var/lock/rstudio-server

# Set the working directory
WORKDIR /home/rstudio

# Expose the RStudio Server port
EXPOSE 8787

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8787/ || exit 1

# Start RStudio Server
CMD ["/usr/lib/rstudio-server/bin/rserver", "--server-daemonize=0"]
