#!/usr/bin/env python3

import argparse
import requests
import attr
import json
import os
from dotenv import load_dotenv


class HawkbitError(Exception):
    pass


@attr.s(eq=False)
class HawkbitMgmtClient:
    host = attr.ib(validator=attr.validators.instance_of(str))
    port = attr.ib(validator=attr.validators.instance_of(int))
    username = attr.ib(default="admin", validator=attr.validators.instance_of(str))
    password = attr.ib(default="admin", validator=attr.validators.instance_of(str))

    def __attrs_post_init__(self):
        if self.port == 443:
            self.url = f"https://{self.host}:{self.port}/rest/v1/{{endpoint}}"
        else:
            self.url = f"http://{self.host}:{self.port}/rest/v1/{{endpoint}}"
        self.id = {}  # To store IDs for recent operations

    def get(self, endpoint: str):
        url = self.url.format(endpoint=endpoint)
        req = requests.get(
            url,
            headers={"Content-Type": "application/json;charset=UTF-8"},
            auth=(self.username, self.password),
        )
        if req.status_code != 200:
            raise HawkbitError(f"HTTP error {req.status_code}: {req.content.decode()}")
        return req.json()

    def post(self, endpoint: str, json_data: dict):
        url = self.url.format(endpoint=endpoint)
        req = requests.post(
            url,
            headers={"Content-Type": "application/json;charset=UTF-8"},
            auth=(self.username, self.password),
            json=json_data,
        )
        if req.status_code not in [200, 201]:
            raise HawkbitError(f"HTTP error {req.status_code}: {req.content.decode()}")
        return req.json()
    
    def put(self, endpoint: str, json_data: dict):
        url = self.url.format(endpoint=endpoint)
        req = requests.put(
            url,
            headers={"Content-Type": "application/json;charset=UTF-8"},
            auth=(self.username, self.password),
            json=json_data,
        )
        if req.status_code not in [200, 204]:
            raise HawkbitError(f"HTTP error {req.status_code}: {req.content.decode()}")
        return req.json() if req.content else None

    def get_targets(self, query_params=""):
        endpoint = f"targets{('?' + query_params) if query_params else ''}"
        return self.get(endpoint)

    def get_targets_by_filter(self, filter_query):
        return self.get(f"targets?q={filter_query}")

    def get_target_actions(self, target_id):
        return self.get(f"targets/{target_id}/actions?limit=10&sort=id:DESC")

    def get_action(self, action_id: str = None, target_id: str = None):
        action_id = action_id or self.id.get("action")
        target_id = target_id or self.id.get("target")
        if not action_id or not target_id:
            raise HawkbitError(
                "Action ID or Target ID not provided and not available from recent operations"
            )
        return self.get(f"targets/{target_id}/actions/{action_id}")

    def get_action_status(self, action_id: str = None, target_id: str = None):
        action_id = action_id or self.id.get("action")
        target_id = target_id or self.id.get("target")
        if not action_id or not target_id:
            raise HawkbitError(
                "Action ID or Target ID not provided and not available from recent operations"
            )
        req = self.get(
            f"targets/{target_id}/actions/{action_id}/status?offset=0&limit=50&sort=id:DESC"
        )
        return req.get("content", [])

    def assign_distribution(self, target_id, distribution_id):
        endpoint = f"targets/{target_id}/assignedDS"
        data = [{"id": distribution_id, "type": "forced"}]
        return self.post(endpoint, data)

    def request_attributes(
        self,
        target_id: str,
        target_name: str,
        controller_id: str,
    ):
        return self.update_target(
            target_id, target_name, controller_id, request_attributes=True
        )

    def update_target(
        self,
        target_id: str,
        target_name: str,
        controller_id: str,
        request_attributes: bool = False,
    ):
        return self.put(
            f"targets/{target_id}",
            {
                "name": target_name,
                "controllerId": controller_id,
                "requestAttributes": request_attributes,
            },
        )


def get_recent_action_status(client, target_id):
    try:
        actions = client.get_target_actions(target_id)
        if actions and "content" in actions and actions["content"]:
            for action in actions["content"]:
                action_id = action.get("id")
                status = action.get("status", "Unknown")
                dist_set = action.get("distributionSet", {})
                dist_name = dist_set.get("name", "Unknown")
                dist_version = dist_set.get("version", "Unknown")
                dist_id = dist_set.get("id", "Unknown")

                action_status = client.get_action_status(action_id, target_id)

                detailed_status = "No detailed status available"
                action_type = "Unknown"
                if action_status:
                    latest_status = action_status[0]  # Most recent status
                    action_type = latest_status.get('type', 'Unknown')
                    detailed_status = f"Type: {action_type}, Status: {status}"
                    if "messages" in latest_status:
                        detailed_status += f", Message: {latest_status['messages'][0] if latest_status['messages'] else 'No message'}"

                needs_update = (
                    action_type.lower() == "error" or
                    "Error" in status or
                    "Failed to install" in detailed_status
                )

                return {
                    "status": status,
                    "distribution": f"{dist_name} ({dist_version})",
                    "distribution_id": dist_id,
                    "details": detailed_status,
                    "needs_update": needs_update,
                    "action_type": action_type  # Added this for clarity in the output
                }
        return {"status": "No recent actions", "distribution": "N/A", "distribution_id": None, "details": "No actions found", "needs_update": False, "action_type": "None"}
    except Exception as e:
        print(f"Error getting action status for target {target_id}: {str(e)}")
        return {"status": "Error", "distribution": "N/A", "distribution_id": None, "details": str(e), "needs_update": False, "action_type": "Error"}

def process_targets(client, channel=None):
    targets_to_update = []
    processed_targets = set()
    limit = 500
    offset = 0
    total_targets = None
    
    filter_query = f'attribute.update_channel=="{channel}"' if channel else ''

    while True:
        try:
            if filter_query:
                targets = client.get_targets(f"offset={offset}&limit={limit}&q={filter_query}")
            else:
                targets = client.get_targets(f"offset={offset}&limit={limit}")
            
            if total_targets is None:
                total_targets = targets.get('total', 0)
                print(f"Total targets{'in the ' + channel + ' channel' if channel else ''}: {total_targets}")
            
            page_targets = targets['content']
            print(f"Processing batch of {len(page_targets)} targets (offset: {offset})")
            
            for target in page_targets:
                target_id = target.get("controllerId")
                target_name = target.get("name")
                
                target_channel = channel if channel else "All channels"
        
                if target_id not in processed_targets:
                    processed_targets.add(target_id)
                    print(f"Processing target: ID: {target_id}, Name: {target_name}, Channel: {target_channel}")
            
                    try:
                        action_status = get_recent_action_status(client, target_id)
                        print(f"Status: {action_status['status']}")
                        print(f"Distribution: {action_status['distribution']}")
                        print(f"Action Type: {action_status['action_type']}")
                        print(f"Details: {action_status['details']}")
                        print(f"Needs update: {action_status['needs_update']}")
                        if action_status["needs_update"]:
                            targets_to_update.append(target_id)
                            print(f"Target {target_id} needs an update.")
                        else:
                            print(f"Target {target_id} does not need to be reassigned a distribution.")
                    except Exception as e:
                        print(f"Error processing target {target_id}: {str(e)}")
                    print("--------------------")
            
            offset += len(page_targets)
            
            if offset >= total_targets or len(page_targets) < limit:
                break
        except Exception as e:
            print(f"Error fetching targets with offset {offset}: {str(e)}")
            break
    
    print(f"Total targets processed: {len(processed_targets)}")
    print(f"Targets that need to be reassigned a distribution: {len(targets_to_update)}")
    return targets_to_update


def get_latest_distribution_by_channel(client, channel):
    """
    Gets the latest distribution for a specific channel
    The channel name is taken from the first word in the distribution name, right before the word EMMC.
    """
    try:
        #Get all distributions
        distributions = client.get("distributionsets?sort=createdAt:DESC&limit=100")
        
        if not distributions or "content" not in distributions or not distributions["content"]:
            raise HawkbitError("No available distributions found")
        
        #Filter distributions that contain "EMMC" and start with the specified channel
        channel_distributions = []
        for dist in distributions["content"]:
            dist_name = dist.get("name", "")
            if "EMMC" in dist_name and dist_name.lower().startswith(channel.lower()):
                channel_distributions.append(dist)
        
        if not channel_distributions:
            print(f"Warning: No distributions found for channel '{channel}'. Check channel name.")
            return None
        
        #We retrieve the most recent distribution, as currently the last three distributions 
        #of each channel are retained.
        latest_dist = channel_distributions[0]
        print(f"Found latest distribution for channel '{channel}': {latest_dist['name']} (ID: {latest_dist['id']})")
        return latest_dist
        
    except Exception as e:
        print(f"Error getting distribution for channel {channel}: {str(e)}")
        return None


def reassign_distribution(client, targets, distribution_id):
    for target_id in targets:
        try:
            print(
                f"Attempting to reassign distribution {distribution_id} to target {target_id}"
            )
            response = client.assign_distribution(target_id, distribution_id)
            print(f"Response from the assignment: {json.dumps(response, indent=2)}")
            print(f"Distribution reassigned to target: {target_id}")
        except HawkbitError as e:
            print(f"Error reassigning distribution to target {target_id}: {str(e)}")
            print("Error details:")
            print(e.args[0] if e.args else "No additional details available")

def load_config():
    load_dotenv()  # This loads the variables from .env file
    
    parser = argparse.ArgumentParser(description="Monitor and update Hawkbit targets")
    parser.add_argument("--host", help="Hawkbit server")
    parser.add_argument("--port", type=int, help="Hawkbit port")
    parser.add_argument("--username", help="Hawkbit user")
    parser.add_argument("--password", help="Hawkbit password")
    parser.add_argument("--channel", help="Update channel (e.g., 'nightly')")
    parser.add_argument("--channels", help="Comma-separated list of update channels (e.g., 'nightly,stable,beta')")

    args = parser.parse_args()

    channels = []
    if args.channels:
        channels = [ch.strip() for ch in args.channels.split(',')]
    elif args.channel:
        channels = [args.channel]
    elif os.getenv("HAWKBIT_CHANNELS"):
        channels = [ch.strip() for ch in os.getenv("HAWKBIT_CHANNELS").split(',')]
    elif os.getenv("HAWKBIT_CHANNEL"):
        if os.getenv("HAWKBIT_CHANNEL").strip(): 
            channels = [os.getenv("HAWKBIT_CHANNEL")]
    
    if not channels:
        channels = ['nightly', 'stable', 'beta', 'rel']

    # Priority: Command line args > Environment variables > Default values
    config = {
        "host": args.host or os.getenv("HAWKBIT_HOST") or "localhost",
        "port": args.port or int(os.getenv("HAWKBIT_PORT", 8080)),
        "username": args.username or os.getenv("HAWKBIT_USERNAME") or "admin",
        "password": args.password or os.getenv("HAWKBIT_PASSWORD") or "admin",
        "channels": channels
    }

    return config


if __name__ == "__main__":
    config = load_config()

    client = HawkbitMgmtClient(
        config["host"], config["port"], username=config["username"], password=config["password"]
    )

    try:
        print(f"Processing the following channels: {', '.join(config['channels'])}")
        
        for channel in config['channels']:
            print(f"\n===== Processing channel: {channel} =====")
            
            #Get the most recent distribution for this channel
            distribution = get_latest_distribution_by_channel(client, channel)
            
            if not distribution:
                print(f"Skipping channel '{channel}' - No suitable distribution found")
                continue
                
            distribution_id = distribution["id"]
            print(f"Using distribution for {channel}: {distribution['name']} (ID: {distribution_id})")

            # Process the targets for this channel
            targets_to_update = process_targets(client, channel)

            if targets_to_update:
                print(f"\nTargets in channel {channel} that need to be reassigned a distribution:")
                for target_id in targets_to_update:
                    print(target_id)

                reassign_distribution(client, targets_to_update, distribution_id)
                print(f"Completed reassigning distribution to targets in channel {channel}")
            else:
                print(f"\nNo targets in channel {channel} need to be reassigned a distribution")
                
    except HawkbitError as e:
        print(f"Error: {str(e)}")
        print("Error details:")
        print(e.args[0] if e.args else "No additional details available")