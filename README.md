# Job Executor deployment script

This script is used to prepare the enviroment for the installation of the Job Executor apllication.\
It installs all the required packages, sets up a shared folder and logs in Docker Hub\
\
This also includes a Python script that is launched when the sh script is launched that automatically generates a Docker compose file.\
It needs all the required configs to be in the folder "configs" and with the names in this format:\
config-<component_name>-<component_id>.json\
Examples:\
config-opcua_rw-1.json\
config-opcua_rw-2.json\
config-mongo_rw-1.json