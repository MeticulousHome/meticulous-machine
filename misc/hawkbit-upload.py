#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
# SPDX-FileCopyrightText: 2021 Enrico Jörns <e.joerns@pengutronix.de>, Pengutronix
# SPDX-FileCopyrightText: 2021 Bastian Krause <bst@pengutronix.de>, Pengutronix
# SPDX-FileCopyrightText: 2024 Mimoja <mimoja@meticuloushome.com>, MeticulousHome Inc.

import time
import os
import attr
import requests as r
import json

from requests_toolbelt import MultipartEncoder, MultipartEncoderMonitor

MAX_IMAGES_ON_SERVER = 3


class HawkbitError(Exception):
    pass


class HawkbitIdStore(dict):
    """dict raising a HawkbitMgmtTestClient related error on KeyError."""

    def __getitem__(self, key):
        try:
            return super().__getitem__(key)
        except KeyError:
            raise HawkbitError(f"{key} not yet created via HawkbitMgmtClient")


@attr.s(eq=False)
class HawkbitMgmtClient:
    """
    Test oriented client for hawkBit's Management API.
    Does not cover the whole Management API, only the parts required for the rauc-hawkbit-updater
    test suite.

    https://eclipse.dev/hawkbit/apis/management_api/
    """

    host = attr.ib(validator=attr.validators.instance_of(str))
    port = attr.ib(validator=attr.validators.instance_of(int))
    username = attr.ib(default="admin", validator=attr.validators.instance_of(str))
    password = attr.ib(default="admin", validator=attr.validators.instance_of(str))
    version = attr.ib(default="1.0", validator=attr.validators.instance_of(str))

    def __attrs_post_init__(self):
        if self.port == 443:
            self.url = f"https://{self.host}:{self.port}/rest/v1/{{endpoint}}"
        else:
            self.url = f"http://{self.host}:{self.port}/rest/v1/{{endpoint}}"
        self.id = HawkbitIdStore()

    def get(self, endpoint: str):
        """
        Performs an authenticated HTTP GET request on `endpoint`.
        Endpoint can either be a full URL or a path relative to /rest/v1/. Expects and returns the
        JSON response.
        """
        url = (
            endpoint
            if endpoint.startswith("http")
            else self.url.format(endpoint=endpoint)
        )
        req = r.get(
            url,
            headers={"Content-Type": "application/json;charset=UTF-8"},
            auth=(self.username, self.password),
        )
        if req.status_code != 200:
            try:
                raise HawkbitError(f"HTTP error {req.status_code}: {req.json()}")
            except:
                raise HawkbitError(
                    f"HTTP error {req.status_code}: {req.content.decode()}"
                )

        return req.json()

    def post(self, endpoint: str, json_data: dict = None, file_name: str = None):
        """
        Performs an authenticated HTTP POST request on `endpoint`.
        If `json_data` is given, it is sent along with the request and JSON data is expected in the
        response, which is in that case returned.
        If `file_name` is given, the file's content is sent along with the request and JSON data is
        expected in the response, which is in that case returned.
        json_data and file_name must not be specified in the same call.
        Endpoint can either be a full URL or a path relative to /rest/v1/.
        """
        assert not (json_data and file_name)

        url = (
            endpoint
            if endpoint.startswith("http")
            else self.url.format(endpoint=endpoint)
        )

        file_size = os.path.getsize(file_name) if file_name else 0

        def upload_logging(monitor):
            percent = monitor.bytes_read / file_size * 100
            if percent - monitor.last_upload_size > 1:
                monitor.last_upload_size = percent
                print(
                    f"{monitor.bytes_read} bytes out of {file_size} sent. ({percent:.0f}%)"
                )

        encoder = (
            MultipartEncoder(fields={"file": (file_name, open(file_name, "rb"))})
            if file_name
            else None
        )
        monitor = (
            MultipartEncoderMonitor(encoder, upload_logging) if file_name else None
        )
        if monitor:
            monitor.last_upload_size = 0

        headers = (
            {"Content-Type": "application/json;charset=UTF-8"} if json_data else None
        )
        headers = {"Content-Type": monitor.content_type} if monitor else headers

        req = r.post(
            url,
            headers=headers,
            auth=(self.username, self.password),
            json=json_data,
            data=monitor,
        )

        if not 200 <= req.status_code < 300:
            try:
                raise HawkbitError(f"HTTP error {req.status_code}: {req.json()}")
            except Exception:
                raise HawkbitError(
                    f"HTTP error {req.status_code}: {req.content.decode()}"
                )

        if json_data or file_name:
            return req.json()

        return None

    def put(self, endpoint: str, json_data: dict):
        """
        Performs an authenticated HTTP PUT request on `endpoint`. `json_data` is sent along with
        the request.
        `endpoint` can either be a full URL or a path relative to /rest/v1/.
        """
        url = (
            endpoint
            if endpoint.startswith("http")
            else self.url.format(endpoint=endpoint)
        )

        req = r.put(url, auth=(self.username, self.password), json=json_data)
        if not 200 <= req.status_code < 300:
            try:
                raise HawkbitError(f"HTTP error {req.status_code}: {req.json()}")
            except Exception:
                raise HawkbitError(
                    f"HTTP error {req.status_code}: {req.content.decode()}"
                )
        return req

    def delete(self, endpoint: str):
        """
        Performs an authenticated HTTP DELETE request on endpoint.
        Endpoint can either be a full URL or a path relative to /rest/v1/.
        """
        url = (
            endpoint
            if endpoint.startswith("http")
            else self.url.format(endpoint=endpoint)
        )

        req = r.delete(url, auth=(self.username, self.password))
        if not 200 <= req.status_code < 300:
            try:
                raise HawkbitError(f"HTTP error {req.status_code}: {req.json()}")
            except:
                raise HawkbitError(
                    f"HTTP error {req.status_code}: {req.content.decode()}"
                )

    def set_config(self, key: str, value: str):
        """
        Changes a configuration `value` of a specific configuration `key`.

        https://eclipse.dev/hawkbit/rest-api/tenant-api-guide.html#_put_restv1systemconfigskeyname
        """
        self.put(f"system/configs/{key}", {"value": value})

    def get_config(self, key: str):
        """
        Returns the configuration value of a specific configuration `key`.

        https://eclipse.dev/hawkbit/rest-api/tenant-api-guide.html#_get_restv1systemconfigskeyname
        """
        return self.get(f"system/configs/{key}")["value"]

    def add_target(self, target_id: str = None, token: str = None):
        """
        Adds a new target with id and name `target_id`.
        If `target_id` is not given, a generic id is made up.
        If `token` is given, set it as target's token, otherwise hawkBit sets a random token
        itself.
        Stores the id of the created target for future use by other methods.
        Returns the target's id.

        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_post_restv1targets
        """
        target_id = target_id or f"test-{time.monotonic()}"
        testdata = {
            "controllerId": target_id,
            "name": target_id,
        }

        if token:
            testdata["securityToken"] = token

        self.post("targets", [testdata])

        self.id["target"] = target_id
        return self.id["target"]

    def get_target(self, target_id: str = None):
        """
        Returns the target matching `target_id`.
        If `target_id` is not given, returns the target created by the most recent `add_target()`
        call.

        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_get_restv1targetstargetid
        """
        target_id = target_id or self.id["target"]

        return self.get(f"targets/{target_id}")

    def delete_target(self, target_id: str = None):
        """
        Deletes the target matching `target_id`.
        If target_id is not given, deletes the target created by the most recent add_target() call.

        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_delete_restv1targetstargetid
        """
        target_id = target_id or self.id["target"]
        self.delete(f"targets/{target_id}")

        if "target" in self.id and target_id == self.id["target"]:
            del self.id["target"]

    def get_attributes(self, target_id: str = None):
        """
        Returns the attributes of the target matching `target_id`.
        If `target_id` is not given, uses the target created by the most recent `add_target()`
        call.
        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_get_restv1targetstargetidattributes
        """
        target_id = target_id or self.id["target"]

        return self.get(f"targets/{target_id}/attributes")

    def add_softwaremodule(self, name: str = None, module_type: str = "os"):
        """
        Adds a new software module with `name`.
        If `name` is not given, a generic name is made up.
        Stores the id of the created software module for future use by other methods.
        Returns the id of the created software module.

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_post_restv1softwaremodules
        """
        name = name or f"software module {time.monotonic()}"
        data = [
            {
                "name": name,
                "version": str(self.version),
                "type": module_type,
            }
        ]

        self.id["softwaremodule"] = self.post("softwaremodules", data)[0]["id"]
        return self.id["softwaremodule"]

    def get_softwaremodule(self, module_id: str = None):
        """
        Returns the sotware module matching `module_id`.
        If `module_id` is not given, returns the software module created by the most recent
        `add_softwaremodule()` call.

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_get_restv1softwaremodulessoftwaremoduleid
        """
        module_id = module_id or self.id["softwaremodule"]

        return self.get(f"softwaremodules/{module_id}")

    def add_targetfilter(self, query: str, name: str = None, auto_assign: bool = False):
        """
        Adds a new target filter with `name`.
        If `name` is not given, a generic name is made up.
        Stores the id of the created target filter for future use by other methods.
        Returns the id of the created target filter

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_post_restv1softwaremodules
        """
        name = name or f"filter {time.monotonic()}"
        data = {"name": name, "query": query, "autoAssignDistributionSet": auto_assign}

        # self.id["targetfilter"] = self.post("targetfilters", data)["id"]
        # return self.id["targetfilter"]
        response = self.post("targetfilters", data)
        self.id["targetfilter"] = response["id"]
        return response

    def get_targetfilter(self, filter_id: str = None):
        """
        Returns the target filter matching `filter_id`.
        If `filter_id` is not given, returns the software module created by the most recent
        `add_targetfilter()` call.

        """
        filter_id = filter_id or self.id["targetfilter"]
        return self.get(f"targetfilters/{filter_id}")

    def get_all_targetfilters(self):
        """
        Returns all target filters.

        """
        limit = 100
        return self.get(f"targetfilters?limit={limit}")

    def update_targetfilter(
        self, filter_id: str, dist_id: str, action_type: str = "forced"
    ):
        """
        Updates an existing target filter to enable automatic assignment.
        """
        json_data = {
            "id": dist_id,
            "type": action_type.lower(),
            "weight": 0,
            "confirmationRequired": False,
        }

        endpoint = f"targetfilters/{filter_id}/autoAssignDS"

        try:
            response = self.post(endpoint, json_data=json_data)

            if response is not None:
                print(
                    f"Auto-assignment successfully configured for the filter {filter_id}"
                )
                return response
            else:
                print(
                    f"No response was received when configuring auto-assignment for the filter {filter_id}"
                )
        except HawkbitError as e:
            print(
                f"Error configuring auto-assignment for the filrter {filter_id}: {str(e)}"
            )

        return None

    def delete_softwaremodule(self, module_id: str = None):
        """
        Deletes the software module matching `module_id`.

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_delete_restv1softwaremodulessoftwaremoduleid
        """
        module_id = module_id or self.id["softwaremodule"]
        self.delete(f"softwaremodules/{module_id}")

        if "softwaremodule" in self.id and module_id == self.id["softwaremodule"]:
            del self.id["softwaremodule"]

    def add_or_update_distributionset(
        self,
        name: str,
        description: str = "",
        module_ids: list = [],
        dist_type: str = "os",
    ):
        named_distributions = self.get_distributionsets_by_name(name)
        if named_distributions:
            existing_dist = named_distributions[0]
            print(
                f"Distribution set '{name}' already exists as ID={existing_dist['id']}. Using existing distribution. Updating version!"
            )
            data = {
                "version": self.version,
            }
            response = self.put(f"distributionsets/{existing_dist['id']}", data).json()
            self.id["distributionset"] = response["id"]
            return response["id"]

        assert isinstance(module_ids, list)
        module_ids = module_ids or [self.id["softwaremodule"]]
        data = [
            {
                "name": name,
                "description": description,
                "version": self.version,
                "modules": [{"id": module_id} for module_id in module_ids],
                "type": dist_type,
            }
        ]
        response = self.post("distributionsets", data)
        self.id["distributionset"] = response[0]["id"]
        return self.id["distributionset"]

    def get_distributionset(self, dist_id: str = None):
        """
        Returns the distribution set matching `dist_id`.
        If `dist_id` is not given, returns the distribution set created by the most recent
        `add_distributionset()` call.

        https://eclipse.dev/hawkbit/rest-api/distributionsets-api-guide.html#_get_restv1distributionsetsdistributionsetid
        """
        dist_id = dist_id or self.id["distributionset"]

        return self.get(f"distributionsets/{dist_id}")

    def delete_distributionset(self, dist_id: str = None):
        """
        Deletes the distrubition set matching `dist_id`.
        If `dist_id` is not given, deletes the distribution set created by the most recent
        `add_distributionset()` call.

        https://eclipse.dev/hawkbit/rest-api/distributionsets-api-guide.html#_delete_restv1distributionsetsdistributionsetid
        """
        dist_id = dist_id or self.id["distributionset"]

        self.delete(f"distributionsets/{dist_id}")

        if "distributionset" in self.id and dist_id == self.id["distributionset"]:
            del self.id["distributionset"]

    def add_artifact(self, file_name: str, module_id: str = None):
        """
        Adds a new artifact specified by `file_name` to the software module matching `module_id`.
        If `module_id` is not given, adds the artifact to the software module created by the most
        recent `add_softwaremodule()` call.
        Stores the id of the created artifact for future use by other methods.
        Returns the id of the created artifact.

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_post_restv1softwaremodulessoftwaremoduleidartifacts
        """
        module_id = module_id or self.id["softwaremodule"]

        self.id["artifact"] = self.post(
            f"softwaremodules/{module_id}/artifacts", file_name=file_name
        )["id"]
        return self.id["artifact"]

    def get_artifact(self, artifact_id: str = None, module_id: str = None):
        """
        Returns the artifact matching `artifact_id` from the software module matching `module_id`.
        If `artifact_id` is not given, returns the artifact created by the most recent
        `add_artifact()` call.
        If `module_id` is not given, uses the software module created by the most recent
        `add_softwaremodule()` call.

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_get_restv1softwaremodulessoftwaremoduleidartifactsartifactid
        """
        module_id = module_id or self.id["softwaremodule"]
        artifact_id = artifact_id or self.id["artifact"]

        return self.get(f"softwaremodules/{module_id}/artifacts/{artifact_id}")["id"]

    def delete_artifact(self, artifact_id: str = None, module_id: str = None):
        """
        Deletes the artifact matching `artifact_id` from the software module matching `module_id`.
        If `artifact_id` is not given, deletes the artifact created by the most recent
        `add_artifact()` call.
        If `module_id` is not given, uses the software module created by the most recent
        `add_softwaremodule()` call.

        https://eclipse.dev/hawkbit/rest-api/softwaremodules-api-guide.html#_delete_restv1softwaremodulessoftwaremoduleidartifactsartifactid
        """
        module_id = module_id or self.id["softwaremodule"]
        artifact_id = artifact_id or self.id["artifact"]

        self.delete(f"softwaremodules/{module_id}/artifacts/{artifact_id}")

        if "artifact" in self.id and artifact_id == self.id["artifact"]:
            del self.id["artifact"]

    def assign_target(
        self, dist_id: str = None, target_id: str = None, params: dict = None
    ):
        """
        Assigns the distribution set matching `dist_id` to a target matching `target_id`.
        If `dist_id` is not given, uses the distribution set created by the most recent
        `add_distributionset()` call.
        If `target_id` is not given, uses the target created by the most recent `add_target()`
        call.
        Stores the id of the assignment action for future use by other methods.

        https://eclipse.dev/hawkbit/rest-api/distributionsets-api-guide.html#_post_restv1distributionsetsdistributionsetidassignedtargets
        """
        dist_id = dist_id or self.id["distributionset"]
        target_id = target_id or self.id["target"]
        testdata = [{"id": target_id}]

        if params:
            testdata[0].update(params)

        response = self.post(f"distributionsets/{dist_id}/assignedTargets", testdata)

        # Increment version to be able to flash over an already deployed distribution
        self.version += 0.1

        self.id["action"] = response.get("assignedActions")[-1].get("id")
        return self.id["action"]

    def get_action(self, action_id: str = None, target_id: str = None):
        """
        Returns the action matching `action_id` on the target matching `target_id`.
        If `action_id` is not given, returns the action created by the most recent
        `assign_target()` call.
        If `target_id` is not given, uses the target created by the most recent `add_target()`
        call.

        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_get_restv1targetstargetidactionsactionid
        """
        action_id = action_id or self.id["action"]
        target_id = target_id or self.id["target"]

        return self.get(f"targets/{target_id}/actions/{action_id}")

    def get_action_status(self, action_id: str = None, target_id: str = None):
        """
        Returns the first (max.) 50 action states of the action matching `action_id` of the target
        matching `target_id` sorted by id.
        If `action_id` is not given, uses the action created by the most recent `assign_target()`
        call.
        If `target_id` is not given, uses the target created by the most recent `add_target()`
        call.

        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_get_restv1targetstargetidactionsactionidstatus
        """
        action_id = action_id or self.id["action"]
        target_id = target_id or self.id["target"]

        req = self.get(
            f"targets/{target_id}/actions/{action_id}/status?offset=0&limit=50&sort=id:DESC"
        )
        return req["content"]

    def cancel_action(
        self, action_id: str = None, target_id: str = None, *, force: bool = False
    ):
        """
        Cancels the action matching `action_id` of the target matching `target_id`.
        If `force=True` is given, cancels the action without telling the target.
        If `action_id` is not given, uses the action created by the most recent `assign_target()`
        call.
        If `target_id` is not given, uses the target created by the most recent `add_target()`
        call.

        https://eclipse.dev/hawkbit/rest-api/targets-api-guide.html#_delete_restv1targetstargetidactionsactionid
        """
        action_id = action_id or self.id["action"]
        target_id = target_id or self.id["target"]

        self.delete(f"targets/{target_id}/actions/{action_id}")

        if force:
            self.delete(f"targets/{target_id}/actions/{action_id}?force=true")

    def get_active_actions(self, target_id):
        actions = self.get(f"targets/{target_id}/actions?status=active,pending")
        return [
            action
            for action in actions.get("content", [])
            if action["status"] in ["active", "pending"]
        ]

    def createRollout(
        self,
        name: str,
        dist_id: str,
        target_filter_query: str,
        autostart: bool = True,
    ):

        rollout_data = {
            "name": name,
            "distributionSetId": dist_id,
            "targetFilterQuery": target_filter_query,
            "type": "forced",
            "weight": 0,
            "confirmationRequired": False,
            "amountGroups": 1,
        }
        if autostart:
            rollout_data["startAt"] = str(int(time.time()))

        return self.post("rollouts", rollout_data)

    def getRolloutByName(self, name):
        # Search for a rollout by name
        rollouts = self.get("rollouts")
        for rollout in rollouts.get("content", []):
            if rollout["name"] == name:
                return rollout
        return None

    def deleteRollout(self, rollout_id):
        try:
            self.delete(f"rollouts/{rollout_id}")
            print(f"Rollout {rollout_id} deleted successfully")
        except HawkbitError as e:
            print(f"Error deleting rollout {rollout_id}: {e}")

    def getAllRollouts(self):
        rollouts = self.get("rollouts")
        return rollouts.get("content", [])

    def get_targets_by_filter(self, filter_query):
        return self.get(f"targets?q={filter_query}")

    def update_target(self, target_id: str, target_name: str, controller_id: str):
        self.put(
            f"targets/{target_id}",
            {
                "name": target_name,
                "controllerId": controller_id,
                "requestAttributes": True,
            },
        )

    def createOrUpdateRollout(self, name, dist_id, target_filter_query, autostart=True):

        channel = args.channel

        targets = self.get_targets_by_filter(target_filter_query)
        print("Targets structure:")
        print(json.dumps(targets, indent=2))

        if isinstance(targets, dict):
            targets = targets.get("content", [])
        elif not isinstance(targets, list):
            print(f"Unexpected targets type: {type(targets)}")
            targets = []

        for target in targets:
            if isinstance(target, dict):
                target_id = target.get('controllerId') or target.get('id')
                target_name = target.get('name', 'Unknown')
            else:
                print(f"Unexpected target type: {type(target)}")
                continue

            if target_id:
                print(f"Processing target: {target_name} (ID: {target_id})")
            
                # Retrieve the target's attributes to verify their channel
                target_attributes = self.get_attributes(target_id)
                target_channel = target_attributes.get('update_channel')
            
                # Only cancel actions if the target belongs to the correct channel
                if target_channel == channel:
                    active_actions = self.get_active_actions(target_id)
                    for action in active_actions:
                        try:
                            print(f"Cancelling active action {action['id']} for target {target_name} (channel: {target_channel})")
                            self.cancel_action(action['id'], target_id, force=True)
                        except HawkbitError as e:
                            print(f"Error cancelling action {action['id']}: {str(e)}")
                else:
                    print(f"Skipping action cancellation for target {target_name} as it belongs to different channel: {target_channel}")
            else:
                print(f"Could not determine target ID for: {target}")

        if not targets:
            print(f"No targets found matching the filter: {target_filter_query}")
            print("Skipping rollout creation.")
            return None

        existing_rollouts = self.getAllRollouts()

        for rollout in existing_rollouts:
            if rollout.get('targetFilterQuery') == target_filter_query:
                print(f"Deleting existing rollout: {rollout['name']}")
                self.deleteRollout(rollout['id'])
            else:
                print(f"Skipping rollout deletion for different channel: {rollout['name']}")

        rollout_data = {
            "name": name,
            "distributionSetId": dist_id,
            "targetFilterQuery": target_filter_query,
            "type": "forced",
            "weight": 0,
            "confirmationRequired": False,
            "amountGroups": 1,
        }
        if autostart:
            rollout_data["startAt"] = str(int(time.time()))

        print(f"Creating new rollout: {name}")
        try:
            return self.post("rollouts", rollout_data)
        except HawkbitError as e:
            print(f"Error creating rollout: {str(e)}")
            return None

    def get_distributionsets_by_name(self, name: str):
        all_distributions_response = self.get("distributionsets")
        all_distributions : list = all_distributions_response.get("content", [])
        named_distributions = [ dist for dist in all_distributions if dist.get('name','Unknown') == name]
        if len(named_distributions) == 0:
            return None
        return named_distributions

    def get_softwaremodule_by_name(self, name, module_type="os", version: str = None):
        # Search for a software module by name and version
        modules = self.get("softwaremodules")
        mods = []
        for module in modules.get("content", []):
            if module["name"] == name:
                mods.append(module)
        if version is not None:
            mods = [module for module in mods if module["version"] == version]
        if(len(mods)) >= 1:
            print(f"Warning: Found multiple distributions with the name '{name}'")
            return mods[0]
        return None

    def add_or_update_softwaremodule(self, name, module_type="os"):
        existing_module = self.get_softwaremodule_by_name(name, module_type)
    
        if existing_module:
            print(f"Software module '{name}' already exists. Using existing module.")
            self.id["softwaremodule"] = existing_module['id']
            return existing_module['id']
    
        data = [
            {
                "name": name,
                "version": str(self.version),
                "type": module_type,
            }
        ]

        response = self.post("softwaremodules", data)
        self.id["softwaremodule"] = response[0]["id"]
        return self.id["softwaremodule"]
    
    def get_all_artifacts(self, module_id):
        artifacts = self.get(f"softwaremodules/{module_id}/artifacts")
        # print("Artifact structure:")
        # print(json.dumps(artifacts, indent=2))
        return artifacts

    def add_or_update_artifact(self, file_name: str, module_id: str = None):
        module_id = module_id or self.id["softwaremodule"]

        existing_artifacts = self.get_all_artifacts(module_id)

        for artifact in existing_artifacts:
            artifact_id = artifact.get("id")
            artifact_name = artifact.get("filename", "Unknown filename")
            if artifact_id:
                print(f"Deleting existing artifact: {artifact_name}")
                self.delete_artifact(artifact_id, module_id)
            else:
                print(f"Warning: Found artifact without ID: {artifact_name}")

        print(f"Uploading new artifact: {file_name}")
        response = self.post(
            f"softwaremodules/{module_id}/artifacts", file_name=file_name
        )
        self.id["artifact"] = response["id"]
        return self.id["artifact"]
    
    def push_new_os_softwaremodule(
        self,
        name,
    ):
        # validate that both name and version does not exist
        existing_module = self.get_softwaremodule_by_name(name, version=self.version)
        if existing_module:
            print(f"module {name} with version {self.version} already exists, using that")
            return existing_module['id']
        
        data = [
            {
                "name": name,
                "version": str(self.version),
                "type": "os"
            }
        ]
        
        response = self.post("softwaremodules", data)
        self.id["newSoftwaremodule"] = response[0]['id']
        return self.id["newSoftwaremodule"]
        
    def push_new_distribution_set_with_os(
        self,
        distribution_name: str,
        softwaremodule_name: str,
        description: str = "",
        module_ids: list = [],
        dist_type: str = "os",
        os_bundle_name: str = None
    ): 
        # Create the corresponding software "OS" Module
        new_module_id = self.push_new_os_softwaremodule(softwaremodule_name)
        
        #define the corresponding data for the distribution set
        modules_list = [new_module_id]
        if isinstance(module_ids, list):            
            modules_list.extend(module_ids)
        
        data = [
            {
                "name": distribution_name,
                "description": description,
                "version": str(self.version),
                "modules": [{"id": module_id} for module_id in modules_list],
                "type": dist_type,
            }
        ]
        
        response = self.post("distributionsets", data)
        self.id["newDistributionset"] = response[0]["id"] 
        
        if os_bundle_name is None:
            print("No bundle file provided to upload")
            return self.id["newDistributionset"], self.id["newSoftwaremodule"], None
        
        # Upload the artifact to the os software module
        new_artifact_id = self.add_or_update_artifact(os_bundle_name, str(new_module_id))
        
        return self.id["newDistributionset"], self.id["newSoftwaremodule"], str(new_artifact_id)
    
    def purge_distributionsets(
        self,
        distributionset_ids: list
    ):
        # validate the distribution_id
        for dist_id in distributionset_ids:
            distributionset_response = self.get_distributionset(dist_id)
            isError = distributionset_response.get("errorCode", None)
            
            if isError:
                error = distributionset_response.get("message", isError)
                print(f"Error getting distributionset with id {dist_id}: {error}")
                continue
            
            # delete the artifacts of all of its modules
            assert distributionset_response.get("modules") is not None, 'attribute "modules" not found in distributionset GET response'
            
            modules = distributionset_response.get("modules", [])
            for module in modules:
                
                existing_artifacts = self.get_all_artifacts(module['id'])

                for artifact in existing_artifacts:
                    artifact_id = artifact.get("id")
                    artifact_name = artifact.get("filename", "Unknown filename")
                    if artifact_id:
                        print(f"Deleting existing artifact: {artifact_name}")
                        self.delete_artifact(artifact_id, module['id'])
                    else:
                        print(f"Warning: Found artifact without ID: {artifact_name}")
                
                self.delete_softwaremodule(module['id'])
                print(f"Deleting existing software module : {module['name']}:{module['version']}")
            
            self.delete_distributionset(dist_id)
            print(f"Deleting existing distribution set : {distributionset_response['name']}:{distributionset_response['version']}")
            return True
    
    def sort_distributions_by_version(
        self,
        dist_name : str
    ):
        from datetime import datetime
        distributions = self.get_distributionsets_by_name(dist_name)
        if distributions is None:
            return None
        
        return sorted(distributions, key=lambda dist: datetime.strptime(dist['version'],'%Y-%m-%dT%H_%M_%S+0000'), reverse=True)
        
def ensure_filter(
    client, filters, query: str, name: str, dist_id: str, action_type: str = "forced"
):
    requested_filter = [f for f in filters if f["query"] == query]
    if len(requested_filter) > 0:
        filter_id = requested_filter[0]["id"]
        result = client.update_targetfilter(filter_id, dist_id, action_type)
        if result:
            print(f"Auto-asignment for the existing filter: {name}")
        else:
            print(f"Error updating auto-assignment for the filter: {name}")
        return requested_filter[0]
    else:
        new_filter = client.add_targetfilter(query, name)
        result = client.update_targetfilter(new_filter["id"], dist_id, action_type)
        if result:
            print(f"Auto-asignment configured for the new filter: {name}")
        else:
            print(f"Error configuring auto-assignment for the new filter: {name}")
        return new_filter


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("host", help="Hawkbit server")
    parser.add_argument("port", help="Hawbit port", type=int)

    parser.add_argument("bundle", help="RAUC bundle to add as artifact")
    parser.add_argument("username", help="Hawkbit user")
    parser.add_argument("password", help="Hawkbit password")
    parser.add_argument("distribution", help="Hawkbit distribution")
    parser.add_argument("softwareModule", help="Hawkbit moduleto add the artifact to")
    parser.add_argument("version", help="Distribution version")
    parser.add_argument("channel", help="Target channel")
    parser.add_argument("bootmode", help="Traget boot mode")

    args = parser.parse_args()

    #Generate the full names fo the distribution ond softwaremodule
    distribution_name = f"{args.distribution}"
    software_module_name = f"{args.softwareModule}"
    client = HawkbitMgmtClient(
        args.host,
        args.port,
        password=args.password,
        username=args.username,
        version=args.version,
    )
    client.set_config("pollingTime", "00:00:30")
    client.set_config("pollingOverdueTime", "00:03:00")
    client.set_config("authentication.targettoken.enabled", True)
    print("Pushing new distribution set")
    (dist_id, module_id, artifact_id) = client.push_new_distribution_set_with_os(distribution_name, software_module_name, os_bundle_name=args.bundle)
    print(f"sorting available {distribution_name} distributions")
    sorted_distributionsets = client.sort_distributions_by_version(distribution_name)
    print("removing extra distributions")
    distribution_ids_to_purge = []
    for index, dist in enumerate(sorted_distributionsets):
        if index >= MAX_IMAGES_ON_SERVER:
            print(f"Marking distributionset {distribution_name}:{dist['version']} to be purged")
            distribution_ids_to_purge.append(dist['id'])
    
    if client.purge_distributionsets(distribution_ids_to_purge):
        print("Distribution sets successfuly purged")

    # Fetch all existing rollouts
    print("Fetching existing rollouts...")
    existing_rollouts = client.getAllRollouts() or []
    
    # Print all existing rollouts for inspection
    print("Existing rollouts:")
    for rollout in existing_rollouts:
        print(json.dumps(rollout, indent=2))

    # Build the targetFilterQuery for the current channel
    current_channel_query = f'attribute.update_channel == "{args.channel}"'
    
    # Debug prints added here
    print("\n=== Debug Information ===")
    print(f"Current channel query: {current_channel_query}")
    print("\nAnalyzing existing rollouts:")
    for rollout in existing_rollouts:
        print(f"\nChecking rollout: {rollout['name']}")
        print(f"Filter query in rollout: {rollout.get('targetFilterQuery')}")
        print(f"Does filter match?: {rollout.get('targetFilterQuery') == current_channel_query}")
        print(f"Rollout channel: {args.channel}")
    print("=== End Debug Information ===\n")
    
    # Filter rollouts by targetFilterQuery
    rollouts_to_delete = [
        rollout for rollout in existing_rollouts
        if rollout.get("targetFilterQuery") == current_channel_query
    ]
    
    # Print the rollouts selected for deletion
    if len(rollouts_to_delete) != 0:
        print("Rollouts selected for deletion:")
        for rollout in rollouts_to_delete:
            print(json.dumps(rollout, indent=2))
    else:
        print(" - No rollouts to delete")

    # Delete filtered rollouts
    for rollout in rollouts_to_delete:
        rollout_id = rollout["id"]
        print(f"Deleting rollout: {rollout['name']} (ID: {rollout_id})")
        client.deleteRollout(rollout_id)
        print(f"Rollout {rollout_id} deleted successfully")

    # Creating a target filter
    filters = client.get_all_targetfilters().get("content") or []

    channel_filter = ensure_filter(
        client,
        filters,
        f'attribute.update_channel == "{args.channel}" and attribute.boot_mode == "{args.bootmode}"',
        f"Downloads from {args.channel} channel, boots from {args.bootmode}",
        dist_id,
        action_type="forced",
    )

    print(f"Channel filter is {channel_filter}")

    # Create or replace the rollout
    raucb_filename = os.path.basename(args.bundle)
    rollout_name = raucb_filename

    target_filter_query = current_channel_query

    print(f"Creating or replacing rollout: {rollout_name}")
    print(f"Using filter query: {target_filter_query}")

    rollout = client.createOrUpdateRollout(
        name=rollout_name,
        dist_id=dist_id,
        target_filter_query=target_filter_query,
        autostart=True,
    )

    if rollout:
        print(f"Rollout created/replaced: {json.dumps(rollout, indent=2)}")
    else:
        print("No rollout was created.")

    print("finished!")
