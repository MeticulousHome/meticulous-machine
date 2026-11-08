"""Exercise the proposed protocol's failure ordering, not real machine safety.

Contract: no suspend without READY/barriers; no commands before fresh recovery;
no actuator re-enable on a timeout, wake gesture or reboot with saved intent.
Budgets below are injected virtual-time inputs, not hardware limits. Mutations
that unlock on READY or accept a cached sample must be rejected by this suite.
"""

from dataclasses import replace
from itertools import product
import unittest

from research.energy_modes.protocol_model import (
    Backend, BarrierProof, Budgets, Firmware, Frame, Preconditions, State,
)


BUDGET = Budgets(prepare=10, armed_lease=100, retry=5, attempts=3)
PROOF = BarrierProof(True, True, True, True, True, True)


class ProtocolTests(unittest.TestCase):
    def pair(self):
        fw = Firmware("boot-a", BUDGET)
        host = Backend(BUDGET)
        host.synchronized(fw.boot, True, fw.state)
        return fw, host

    def armed(self):
        fw, host = self.pair()
        fw.receive(host.begin("session-a", 0), 0)
        ready = fw.barrier_complete(PROOF, 1)
        host.receive(ready, 1)
        self.assertFalse(host.commands_allowed)
        self.assertTrue(fw.inhibited)
        return fw, host

    def recover(self, fw, host, now=5):
        awake = fw.receive(host.recover("challenge-a", now), now)
        host.receive(awake, now)
        release = host.receive(fw.fresh_sample(), now + 1)
        self.assertIsNotNone(release)
        self.assertFalse(host.commands_allowed)
        reply = fw.receive(release, now + 1)
        host.receive(reply, now + 1)
        return release

    def test_busy_preheat_update_fault_or_output_rejects_on_either_peer(self):
        for field, value in (("idle", False), ("preheat", True), ("update", True),
                             ("fault", True), ("outputs_zero", False)):
            with self.subTest(field=field):
                unsafe = replace(Preconditions(), **{field: value})
                fw, host = self.pair()
                with self.assertRaises(ValueError):
                    host.begin("s", 0, unsafe)
                request = host.begin("s", 0)
                reject = fw.receive(request, 0, unsafe)
                self.assertEqual(reject.kind, "reject")
                host.receive(reject, 0)
                self.assertTrue(host.commands_allowed)

    def test_old_firmware_and_som_off_are_not_supported(self):
        for capability, mode in ((False, "deep"), (True, "off")):
            fw, host = self.pair()
            host.supported = capability
            with self.assertRaises(ValueError):
                host.begin("s", 0, mode=mode)
            self.assertEqual(fw.state, State.ACTIVE)

    def test_every_barrier_is_required_before_ready(self):
        for field in vars(PROOF):
            with self.subTest(field=field):
                fw, host = self.pair()
                fw.receive(host.begin("s", 0), 0)
                self.assertIsNone(fw.barrier_complete(replace(PROOF, **{field: False}), 1))
                self.assertFalse(host.enter_suspend(2, True, True))
                self.assertEqual(fw.output_request(90, 90), (0, 0))

    def test_all_ordinary_tx_sources_are_gated_during_inhibit(self):
        fw, host = self.armed()
        for source in ("telemetry", "notification", "event", "mileage", "logger",
                       "cout", "stdio", "Serial", "sdk", "future-producer"):
            self.assertIsNone(fw.normal_tx(source, "bytes"))
        self.assertIsNotNone(fw.local_input(2))  # Designated wake/control path.
        self.assertEqual(fw.output_request(90, 90), (0, 0))

    def test_suspend_requires_ready_kernel_barrier_and_fallback(self):
        for kernel, fallback in product((False, True), repeat=2):
            fw, host = self.armed()
            self.assertEqual(host.enter_suspend(2, kernel, fallback), kernel and fallback)
            self.assertFalse(host.commands_allowed)
            host.suspend_returned()  # Also used for an aborted/failed syscall.
            self.assertFalse(host.commands_allowed)
            self.assertTrue(fw.inhibited)

    def test_wake_before_ready_after_ready_or_after_suspend_never_starts_a_brew(self):
        for stage in ("before-ready", "after-ready", "asleep"):
            with self.subTest(stage=stage):
                fw, host = self.pair()
                fw.receive(host.begin("session-a", 0), 0)
                if stage != "before-ready":
                    host.receive(fw.barrier_complete(PROOF, 1), 1)
                if stage == "asleep":
                    self.assertTrue(host.enter_suspend(2, True, True))
                host.receive(fw.local_input(3), 3)
                self.assertFalse(host.enter_suspend(3, True, True))
                self.assertEqual(fw.output_request(90, 90), (0, 0))
                self.recover(fw, host)
                self.assertTrue(host.commands_allowed)
                self.assertEqual(fw.outputs, (0, 0))

    def test_cached_out_of_order_and_wrong_identity_replies_cannot_unlock(self):
        fw, host = self.armed()
        awake = fw.receive(host.recover("challenge-a", 5), 5)
        fresh = fw.fresh_sample()
        # Receiving a sample before the baseline acknowledgement is insufficient.
        self.assertIsNone(host.receive(fresh, 6))
        for bad in (replace(awake, boot="old-boot"), replace(awake, session="old-session"),
                    replace(awake, challenge="old-challenge")):
            host.receive(bad, 6)
            self.assertIsNone(host.baseline)
        host.receive(awake, 6)
        self.assertIsNone(host.receive(replace(fresh, sample=awake.sample), 6))
        self.assertIsNone(host.receive(Frame("released", host.session, host.boot, host.challenge), 6))
        self.assertFalse(host.commands_allowed)
        release = host.receive(fresh, 7)
        host.receive(fw.receive(release, 7), 7)
        self.assertTrue(host.commands_allowed)

    def test_lost_ready_is_bounded_and_recoverable_without_uninhibiting(self):
        fw, host = self.pair()
        fw.receive(host.begin("session-a", 0), 0)
        fw.barrier_complete(PROOF, 1)  # Drop reply.
        host.tick(BUDGET.prepare)
        self.assertEqual(host.state, State.FAULT)
        self.assertTrue(fw.inhibited)
        self.recover(fw, host, 11)
        self.assertTrue(host.commands_allowed)

    def test_lost_wake_retries_are_bounded_and_expiry_keeps_outputs_off(self):
        fw, host = self.armed()
        emitted = [fw.local_input(2)]
        for now in (7, 12, 17, 1000):
            emitted.append(fw.tick(now))
        self.assertEqual(len([m for m in emitted if m]), BUDGET.attempts)
        self.assertEqual(fw.state, State.FAULT)
        self.assertEqual(fw.output_request(90, 90), (0, 0))
        self.assertFalse(host.commands_allowed)

    def test_lease_expiry_and_host_crash_never_restore_output(self):
        fw, _ = self.armed()
        crashed_host = Backend(BUDGET)
        self.assertFalse(crashed_host.commands_allowed)
        self.assertEqual(fw.tick(1 + BUDGET.armed_lease).kind, "wake")
        self.assertEqual(fw.output_request(90, 90), (0, 0))
        crashed_host.synchronized(fw.boot, True, fw.state)
        self.assertFalse(crashed_host.commands_allowed)

    def test_reboot_with_durable_intent_starts_inhibited(self):
        fw, host = self.armed()
        restarted = Firmware("boot-b", BUDGET, fw.durable_session)
        self.assertEqual(restarted.output_request(90, 90), (0, 0))
        self.assertIsNone(restarted.normal_tx("telemetry", "bytes"))
        host.receive(Frame("ready", host.session, restarted.boot), 2)
        self.assertFalse(host.commands_allowed)

    def test_lost_released_reply_is_retried_without_replaying_outputs(self):
        fw, host = self.armed()
        host.receive(fw.receive(host.recover("challenge-a", 5), 5), 5)
        release = host.receive(fw.fresh_sample(), 6)
        fw.receive(release, 6)  # Drop RELEASED.
        self.assertFalse(host.commands_allowed)
        retry = host.tick(6 + BUDGET.retry)
        self.assertEqual(retry, release)
        host.receive(fw.receive(retry, 11), 11)
        self.assertTrue(host.commands_allowed)
        self.assertEqual(fw.outputs, (0, 0))

    def test_late_recovery_ack_cannot_extend_the_absolute_budget(self):
        fw, host = self.armed()
        awake = fw.receive(host.recover("challenge-a", 5), 5)
        host.receive(awake, 5 + BUDGET.retry * BUDGET.attempts)
        self.assertEqual(host.state, State.FAULT)
        self.assertIsNone(host.tick(1000))
        fw.tick(1000)
        self.assertEqual(fw.output_request(90, 90), (0, 0))


if __name__ == "__main__":
    unittest.main()
