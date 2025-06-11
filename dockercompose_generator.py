import os
import re
import yaml
import sys

if len(sys.argv) < 2:
    print("Error: Missing required parameter.", file=sys.stderr)
    sys.exit(1)
else:
    docker_hub_account = sys.argv[1]


# --- Custom scalar string for folded formatting ---
class FoldedScalarString(str):
    pass

# --- Custom dumper ---
class CustomDumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)

# --- Represent FoldedScalarString with style='>' ---
def folded_scalar_representer(dumper, data):
    return dumper.represent_scalar('tag:yaml.org,2002:str', str(data), style='>')

# --- Represent lists using block style ---
def block_list_representer(dumper, data):
    return dumper.represent_sequence('tag:yaml.org,2002:seq', data, flow_style=False)

# --- Register the representers ---
CustomDumper.add_representer(FoldedScalarString, folded_scalar_representer)
CustomDumper.add_representer(list, block_list_representer)

# Custom function to clean and format the string correctly for folded scalar style
def clean_folded_string(input_str):
    input_str = input_str.strip()

    folded_lines = '\n'.join(line.strip() for line in input_str.splitlines() if line.strip())
    # Return as FoldedScalarString for proper YAML representation
    return FoldedScalarString(folded_lines+'\n')

# Directory containing config files
input_folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'configs')


# Pattern to match config files like config-nginx-1.json, config-redis-2.json, etc.
pattern = re.compile(r'^config-([\w\d\-]+)-\d+\.json$')

services = {}

# Adding custom ones
services['mongo_db'] = {
    'image': 'mongo:4.4',
    'container_name': 'mongo_db',
    'healthcheck': {
      'test': ["CMD", "mongosh", "--eval", "\'db.runCommand(\\\"ping\\\").ok\'", "--quiet"],
      'interval': '10s',
      'timeout': '5s',
      'retries': 3,
      'start_period': '20s'
    },
    'volumes': ['mongodb_data:/data/db'],
    'restart': 'always',
    'networks': ['recepy-manager']
}

services['orchestrator'] = {
    'container_name': 'orchestrator',
    'image': f'{docker_hub_account}/orchestrator',
    # 'volumes': [
    #     f"{input_folder}/config-orchestrator-1.json:/app/config/config.json"
    # ],
    'healthcheck': {
        'test': clean_folded_string(
            "curl -fsSL http://localhost:3000/api/health &&\n"
            "curl -fsSL http://localhost:3001/api/health\n"
        ),
        'interval': '10s',
        'timeout': '5s',
        'retries': 3,
        'start_period': '20s'
    },
    'volumes': ['/home/shares/csv_import/:/home/shares/csv_import', 
                './configs/config-orchestrator-1.json:/app/config/config.json'],
    'ports': ['3000:3000', '4000:4000'],
    'restart': 'always',
    'networks': ['recepy-manager']
}


for filename in os.listdir(input_folder):
    # i skip the orchestrator config file since it's custom handled
    if 'orchestrator' in filename:
        continue

    match = pattern.match(filename)
    if match:
        # Extract the image name (e.g., modbus_rw, opcua_rw)
        image = match.group(1)

        # Create a unique service name based on the image name and config file identifier
        # Extract 1, 2, etc.
        config_identifier = filename.split('-')[-1].split('.')[0]
        service_name = f"{image}_{config_identifier}"

        # Add the service with the config file mounted
        services[service_name] = {
            'container_name': service_name,
            'image': f'{docker_hub_account}/'+image,
            'volumes': [
                f"./configs/{filename}:/app/config.json"
            ],
            'healthcheck': {
                'test': clean_folded_string(
                    "curl -fsSL http://localhost:5000/api/health\n"
                ),
                'interval': '10s',
                'timeout': '5s',
                'retries': 3,
                'start_period': '20s'
            },
            'restart': 'always',
            'networks': ['recepy-manager']
        }


# Create the Docker Compose file content
docker_compose = {
    'services': services,
    'volumes': {
        'mongodb_data': {
            'driver': 'local'
        }
    },
    'networks': {
        'recepy-manager': {
            'name': 'recepy-manager'
        }
    }
}

# Step 6: Dump using the custom dumper
yaml_output = yaml.dump(
    docker_compose,
    Dumper=CustomDumper,
    default_flow_style=False,
    sort_keys=False,
    indent=2,
    width=120,
    allow_unicode=True
)

# Post-process the YAML output to strip extra newlines
yaml_output = yaml_output.replace('\n\n', '\n')
yaml_output = yaml_output.replace("'''", "'")

output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'docker-compose.yml')

# Now write the cleaned YAML output to the file
with open(output_path, 'w') as f:
    f.write(yaml_output)

print("docker-compose.yml generated.")
