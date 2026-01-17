# Frappe 1-Tap Install

This project provides a simple one-tap installation for a Frappe/ERPNext environment using Docker.

## Overview

This setup simplifies the process of getting a Frappe instance up and running. It uses Docker and Docker Compose to create and manage the necessary containers for the Frappe framework, including the database and other services.

## Prerequisites

Before you begin, ensure you have the following installed on your system:
*   [Docker](https://docs.docker.com/get-docker/)
*   [Docker Compose](https://docs.docker.com/compose/install/)

## Installation and Usage

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/SwayAlgo/Frappe1TapInstall.git
    cd Frappe1TapInstall
    ```

2.  **Run the initialization script:**
    This script will set up the environment, pull the necessary Docker images, and start the services.
    ```bash
    ./init.sh
    ```
    Follow the on-screen prompts to complete the setup. Once the script finishes, your Frappe/ERPNext instance will be available at `http://localhost:8000`.

## Automatic Restore on Startup

The system is designed to be resilient against data loss. When you start the environment with `./init.sh` or `docker-compose up`:

1.  It will check for any existing backups in the `persistent/backups/` directory.
2.  If backups are found, it will automatically restore the **most recent** one.
3.  If no backups are found, it will perform a fresh installation of Frappe/ERPNext.

## Stopping the Environment and Data Safety

To ensure your data is backed up before you stop the containers, **do not use `docker-compose down` directly**. Instead, use the provided shutdown script:

```bash
./shutdown.sh
```

This script will:
1.  Create a final, up-to-the-minute backup of your site.
2.  Safely stop and remove the Docker containers.

The `backup` service also runs in the background to create a full backup automatically every week. All backups are stored in the `persistent/backups/` directory on your host machine.

## Manual Restore

If you need to manually restore a specific backup file:

1.  Place your backup file (e.g., `my_backup.sql.gz`) into the `persistent/backups/` directory.
2.  Run the restore script, passing the filename as an argument:
    
    ```bash
    docker-compose exec frappe bash /workspace/restore.sh my_backup.sql.gz
    ```

The script will handle restoring both the database and the associated site files.

## Included Files

*   `docker-compose.yml`: Defines the services, networks, and volumes for the Docker application.
*   `Dockerfile`: Contains the instructions to build the custom Frappe Docker image.
*   `init.sh`: The main script to initialize the Frappe environment.
*   `backup.sh`: A script to perform backups of the Frappe sites.
*   `restore.sh`: A script to manually restore a site from a backup.
*   `shutdown.sh`: The recommended script to safely stop the environment and create a final backup.
*   `.dockerignore`: Specifies files and directories to be excluded from the Docker build context.
