"""Executable ErP protocol proposal, NOT a machine driver or firmware implementation.

Pure event model: no clocks, files, subprocesses, UART or GPIO are accessed.
The caller supplies time and verified barriers. This explores ordering/failure
requirements before changing production backend/firmware. See protocol-design.md.
"""

from dataclasses import dataclass
from enum import Enum, auto


class State(Enum):
    UNSYNCED = auto()
    ACTIVE = auto()
    PREPARING = auto()
    ARMED = auto()
    SUSPENDED = auto()
    WAKING = auto()
    RECOVERING = auto()
    RELEASING = auto()
    FAULT = auto()


@dataclass(frozen=True)
class Frame:
    kind: str
    session: str
    boot: str
    challenge: str = ""
    sample: int = 0


@dataclass(frozen=True)
class Preconditions:
    idle: bool = True
    preheat: bool = False
    update: bool = False
    fault: bool = False
    outputs_zero: bool = True

    @property
    def safe(self):
        return self.idle and not (self.preheat or self.update or self.fault) and self.outputs_zero


@dataclass(frozen=True)
class BarrierProof:
    # These must eventually be supplied by real adapters, never inferred from
    # status == idle or from cached Socket.IO telemetry.
    actuator_gate_closed: bool
    outputs_zero: bool
    heater_timer_disarmed: bool
    all_normal_tx_gated: bool
    tx_drained: bool
    intent_durable: bool

    @property
    def ready(self):
        return all(vars(self).values())


@dataclass(frozen=True)
class Budgets:
    # Deliberately no production defaults. Test values are simulation inputs,
    # not measured hardware deadlines or power-management policy.
    prepare: int
    armed_lease: int
    retry: int
    attempts: int

    def __post_init__(self):
        if min(self.prepare, self.armed_lease, self.retry, self.attempts) <= 0:
            raise ValueError("budgets must be positive")


class Firmware:
    def __init__(self, boot, budgets, durable_session=None):
        self.boot = boot
        self.budgets = budgets
        self.session = durable_session or ""
        self.durable_session = durable_session
        self.state = State.FAULT if durable_session else State.ACTIVE
        self.outputs = (0, 0)
        self.challenge = ""
        self.sample = 0
        self.resume_baseline = None
        self.deadline = 0
        self.attempts = 0

    @property
    def inhibited(self):
        return self.state != State.ACTIVE

    def output_request(self, motor, heater):
        self.outputs = (0, 0) if self.inhibited else (motor, heater)
        return self.outputs

    def normal_tx(self, source, payload):
        # The adapter must route EVERY ordinary producer through this boundary;
        # this model does not establish that stdio/SDK/Serial do so today.
        return (source, payload) if self.state == State.ACTIVE else None

    def receive(self, frame, now, conditions=Preconditions()):
        if frame.boot != self.boot:
            return None
        if frame.kind == "prepare":
            if not frame.session or self.state != State.ACTIVE:
                return None
            if not conditions.safe:
                return Frame("reject", frame.session, self.boot)
            self.session = frame.session
            self.state = State.PREPARING
            self.outputs = (0, 0)
            self.deadline = now + self.budgets.prepare
            # No READY here: stop PWM/timer, gate/drain all TX and durably save
            # intent first, under the real adapter's concurrency barrier.
            return None
        if frame.session != self.session:
            return None
        if self.state == State.RECOVERING and now >= self.deadline:
            self.state = State.FAULT
            return None
        if frame.kind == "resume" and frame.challenge and self.inhibited:
            if self.state == State.RECOVERING and frame.challenge == self.challenge:
                return Frame("awake", self.session, self.boot, self.challenge, self.resume_baseline)
            if frame.challenge == self.challenge:
                return None
            self.state = State.RECOVERING
            self.challenge = frame.challenge
            self.resume_baseline = self.sample
            self.deadline = now + self.budgets.retry * self.budgets.attempts
            return Frame("awake", self.session, self.boot, self.challenge, self.sample)
        if frame.kind == "release" and frame.challenge == self.challenge and self.challenge:
            if self.state == State.ACTIVE:
                # Lost RELEASED reply: idempotent response, no replayed output.
                return Frame("released", self.session, self.boot, self.challenge)
            if self.state == State.RECOVERING and self.sample > self.resume_baseline:
                self.outputs = (0, 0)
                self.durable_session = None
                self.state = State.ACTIVE
                return Frame("released", self.session, self.boot, self.challenge)
        return None

    def barrier_complete(self, proof, now):
        if self.state != State.PREPARING or now >= self.deadline or not proof.ready:
            return None
        self.durable_session = self.session
        self.state = State.ARMED
        self.deadline = now + self.budgets.armed_lease
        return Frame("ready", self.session, self.boot)

    def local_input(self, now):
        if not self.inhibited:
            return None  # Ordinary application handling is outside this model.
        # Consume this gesture; never replay it as brew/preheat after recovery.
        if self.state not in (State.WAKING, State.RECOVERING):
            self.state = State.WAKING
            self.attempts = 1
            self.deadline = now + self.budgets.retry
            return Frame("wake", self.session, self.boot)
        return None

    def fresh_sample(self):
        self.sample += 1
        if self.state == State.RECOVERING:
            return Frame("sample", self.session, self.boot, self.challenge, self.sample)
        return None

    def tick(self, now):
        if self.state == State.ACTIVE or now < self.deadline:
            return None
        if self.state in (State.PREPARING, State.ARMED):
            return self.local_input(now)  # Lease expiry wakes but NEVER releases.
        if self.state == State.WAKING and self.attempts < self.budgets.attempts:
            self.attempts += 1
            self.deadline = now + self.budgets.retry
            return Frame("wake", self.session, self.boot)
        self.state = State.FAULT
        self.outputs = (0, 0)
        return None


class Backend:
    def __init__(self, budgets):
        self.budgets = budgets
        self.state = State.UNSYNCED
        self.boot = ""
        self.session = ""
        self.challenge = ""
        self.baseline = None
        self.deadline = 0
        self.attempts = 0
        self.pending = None
        self.supported = False
        self.expires_at = 0

    @property
    def commands_allowed(self):
        return self.state == State.ACTIVE

    def synchronized(self, boot, capability, peer_state):
        # Placeholder for a fresh version/capability handshake, not ESPInfo
        # cache. Never use it to clear a possibly armed session after a crash.
        if self.state != State.UNSYNCED:
            raise ValueError("synchronization cannot bypass an active transaction")
        self.boot = boot
        self.supported = capability
        self.state = State.ACTIVE if peer_state == State.ACTIVE else State.FAULT

    def begin(self, session, now, conditions=Preconditions(), mode="deep"):
        if not self.commands_allowed or not self.supported or not conditions.safe or mode != "deep":
            raise ValueError("unsupported or busy transition")
        if not session or session == self.session:
            raise ValueError("fresh session required")
        self.session = session
        self.state = State.PREPARING
        self.deadline = now + self.budgets.prepare
        return Frame("prepare", session, self.boot)

    def recover(self, challenge, now):
        if not challenge or challenge == self.challenge or not self.session:
            raise ValueError("fresh recovery challenge required")
        self.challenge = challenge
        self.baseline = None
        self.state = State.RECOVERING
        self.pending = Frame("resume", self.session, self.boot, challenge)
        self.attempts = 1
        self.deadline = now + self.budgets.retry
        self.expires_at = now + self.budgets.retry * self.budgets.attempts
        return self.pending

    def receive(self, frame, now):
        if frame.boot != self.boot or frame.session != self.session:
            return None
        if self.state in (State.RECOVERING, State.RELEASING) and now >= self.expires_at:
            self.state = State.FAULT
            self.pending = None
            return None
        if frame.kind == "reject" and self.state == State.PREPARING:
            self.state = State.ACTIVE
        elif frame.kind == "ready" and self.state == State.PREPARING and now < self.deadline:
            self.state = State.ARMED
        elif frame.kind == "wake" and self.state in (State.PREPARING, State.ARMED, State.SUSPENDED):
            # Caller starts recovery with a newly generated challenge.
            self.state = State.FAULT
        elif frame.challenge == self.challenge and self.challenge:
            if frame.kind == "awake" and self.state == State.RECOVERING and self.baseline is None:
                self.baseline = frame.sample
            elif frame.kind == "sample" and self.state == State.RECOVERING:
                if self.baseline is not None and frame.sample > self.baseline:
                    self.state = State.RELEASING
                    self.pending = Frame("release", self.session, self.boot, self.challenge)
                    self.attempts = 1
                    self.deadline = now + self.budgets.retry
                    self.expires_at = now + self.budgets.retry * self.budgets.attempts
                    return self.pending
            elif frame.kind == "released" and self.state == State.RELEASING:
                self.state = State.ACTIVE
                self.pending = None
        return None

    def enter_suspend(self, now, kernel_barrier_ok, rtc_fallback_armed):
        if self.state != State.ARMED or now >= self.deadline or not kernel_barrier_ok or not rtc_fallback_armed:
            if self.state != State.ACTIVE:
                self.state = State.FAULT
            return False
        self.state = State.SUSPENDED
        return True

    def suspend_returned(self):
        # Success, abort and syscall failure ALL require recovery. A running
        # backend, cached sensors or a kernel success counter cannot unlock it.
        if self.state != State.ACTIVE:
            self.state = State.FAULT

    def tick(self, now):
        if now < self.deadline:
            return None
        if self.state in (State.PREPARING, State.ARMED):
            self.state = State.FAULT
        elif self.state in (State.RECOVERING, State.RELEASING):
            if now < self.expires_at and self.attempts < self.budgets.attempts:
                self.attempts += 1
                self.deadline = now + self.budgets.retry
                return self.pending
            self.state = State.FAULT
            self.pending = None
        return None
