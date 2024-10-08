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

    def get_targets(self):
        return self.get(f"targets")

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

    def get_latest_distribution(self):
        distributions = self.get("distributionsets?sort=createdAt:DESC&limit=1")
        if distributions and "content" in distributions and distributions["content"]:
            return distributions["content"][0]
        raise HawkbitError("No available distributions found")

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


def get_recent_action_status(client, target_id, latest_distribution_id):
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
                    action_type not in ["running", "finished"] or
                    "Failed to install" in detailed_status or
                    "canceled" in detailed_status.lower() or
                    "force quit" in detailed_status.lower() or
                    (action_type == "finished" and dist_id != latest_distribution_id)
                )

                return {
                    "status": status,
                    "distribution": f"{dist_name} ({dist_version})",
                    "distribution_id": dist_id,
                    "details": detailed_status,
                    "needs_update": needs_update,
                    "action_type": action_type
                }
        return {"status": "No recent actions", "distribution": "N/A", "distribution_id": None, "details": "No actions found", "needs_update": True, "action_type": "Unknown"}
    except HawkbitError as e:
        print(f"Error getting action status for target {target_id}: {str(e)}")
        return {"status": "Error", "distribution": "N/A", "distribution_id": None, "details": str(e), "needs_update": True, "action_type": "Unknown"}

def process_targets(client, channel, latest_distribution_id):
    if channel is not None:
        filter_query = f'attribute.update_channel=={channel}'
        try:
            targets = client.get_targets_by_filter(filter_query)
            print(f"Targets with channel '{channel}':")
        except HawkbitError as e:
            print(f"Error fetching targets: {str(e)}")
            return []
    else:
        targets = client.get_targets()

    targets_to_update = []

    if isinstance(targets, dict) and "content" in targets:
        for target in targets["content"]:
            target_id = target.get("controllerId")
            target_name = target.get("name")
            try:
                print(f"Processing target: ID: {target_id}, Name: {target_name}")
                action_status = get_recent_action_status(client, target_id, latest_distribution_id)

                print(f"Status: {json.dumps(action_status, indent=2)}")
                print("--------------------")

                if action_status["needs_update"] and action_status["action_type"] != "running" and action_status["distribution_id"] != latest_distribution_id:
                    targets_to_update.append(target_id)
            except Exception as e:
                print(f"Error processing target {target_id}: {str(e)}")

    return targets_to_update


def reassign_distribution(client, targets, distribution_id):
    for target_id in targets:
        try:
            print(
                f"Attempting to reassign distribution {distribution_id} al target {target_id}"
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

    args = parser.parse_args()

    # Priority: Command line args > Environment variables > Default values
    config = {
        "host": args.host or os.getenv("HAWKBIT_HOST") or "localhost",
        "port": args.port or int(os.getenv("HAWKBIT_PORT", 8080)),
        "username": args.username or os.getenv("HAWKBIT_USERNAME") or "admin",
        "password": args.password or os.getenv("HAWKBIT_PASSWORD") or "admin",
        "channel": args.channel or os.getenv("HAWKBIT_CHANNEL")
    }

    return config


if __name__ == "__main__":
    config = load_config()

    client = HawkbitMgmtClient(
        config["host"], config["port"], username=config["username"], password=config["password"]
    )

    try:
        latest_distribution = client.get_latest_distribution()
        distribution_id = latest_distribution["id"]
        print(
            f"Latest distribution found: {latest_distribution['name']} (ID: {distribution_id})"
        )

        targets_to_update = process_targets(client, config["channel"], distribution_id)

        if targets_to_update:
            print("\nTargets that need updating:")
            for target_id in targets_to_update:
                print(target_id)

            reassign_distribution(client, targets_to_update, distribution_id)
        else:
            print("\nNo targets need updating.")
    except HawkbitError as e:
        print(f"Error: {str(e)}")
        print("Error details:")
        print(e.args[0] if e.args else "No additional details available")
