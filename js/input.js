/* =====================================================================
   MEWD — input
   =====================================================================

   One layer over keyboard, mouse, gamepad and touch, because the game
   should not care and there is no version of caring that ends well.
   Everything downstream reads the same four numbers and the same set of
   named buttons.

     move.x   -1 .. 1   strafe
     move.y   -1 .. 1   forward
     look.x             yaw this frame, in radians
     look.y             pitch this frame, in radians

   Buttons are edge-detected here rather than downstream: `pressed()` is
   true for exactly one frame, `down()` for as long as it is held. Weapon
   switching wants the first, the flamethrower wants the second, and
   working that out at each call site is how you end up with a
   flamethrower that fires once.

   MOUSE LOOK is pointer-locked and accumulates between frames rather
   than being sampled, so a fast flick is not lost between two vsyncs.

   TOUCH is written into `touch` by touch.js and read here like any other
   device. The two never fight because the game is in one MODE at a time,
   and the mode is whichever device spoke last: a phone with a keyboard
   plugged in is a desktop until it is tapped, and a laptop with a screen
   you can poke is a phone until a key goes down. Pointer lock belongs to
   the desktop mode only — on a phone it fails, and on a phone with a
   mouse it would be a mistake.
   ===================================================================== */

const KEYMAP = {
  KeyW: 'forward', ArrowUp: 'forward',
  KeyS: 'back', ArrowDown: 'back',
  KeyA: 'left', KeyQ: 'left',
  KeyD: 'right', KeyE: 'right',
  ArrowLeft: 'turnLeft', ArrowRight: 'turnRight',
  ShiftLeft: 'run', ShiftRight: 'run',
  /* SPACE IS JUMP NOW, at the user's request, and F is use — the
     arrangement every game since Quake has settled on */
  Space: 'jump', KeyF: 'use',
  ControlLeft: 'attack', ControlRight: 'attack',
  Digit1: 'weapon1', Digit2: 'weapon2', Digit3: 'weapon3', Digit4: 'weapon4',
  Digit5: 'weapon5', Digit6: 'weapon6', Digit7: 'weapon7',
  /* ZOOM, which the game had no use for until the lance arrived with a
     screen on it: a press steps the magnification round — see ZOOMS in
     js/scope.js. The right mouse button is where every game since Halo
     has put this, and Z is for the hand that is not on a mouse. */
  KeyZ: 'zoom', KeyC: 'zoom',
  Tab: 'map', KeyM: 'map',
  Escape: 'pause', KeyP: 'pause',
};

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    this.keys = new Set();
    this.prev = new Set();
    /* A press is remembered until the next sample even if the key is
       already up again: the world ticks 35 times a second and a tap can
       be shorter than that, and a pause key that only works if you hold
       it long enough is a pause key that sometimes does not work. */
    this.latch = new Set();
    this.mouseDown = false;
    this.mouseRight = false;
    this.mouseRightPulse = false;
    this.mouseDX = 0; this.mouseDY = 0;
    this.wheel = 0;
    this.locked = false;
    this.sensitivity = 0.0022;
    /* and what the scope multiplies it by while it is narrowed — see
       sample(). Nothing but js/main.js writes it. */
    this.zoomScale = 1;
    /* the scope's three presses, kept until js/main.js takes them — see
       sample() and takeScope() */
    this.zoomPressed = false;
    this.zoomStep = false;
    this.aimToggle = false;
    this.invertY = false;
    this.touch = {
      move: { x: 0, y: 0 }, look: { x: 0, y: 0 },
      attack: false, use: false, usePulse: false, jumpPulse: false, zoomPulse: false,
      aimPulse: false, pausePulse: false, run: false, weapon: 0,
    };
    /* WHETHER A PAD IS IN CHARGE, which is a different question from
       which MODE the game is in: a phone with a controller paired is
       still a phone — it has no keyboard, its menus are tapped — but
       while the pad is being used the thumb controls are in the way
       of the picture and are faded off it (see js/touch.js and
       #touch.pad in the CSS). True from the first button or stick
       movement until the next touch, and announced on the way over. */
    this.padHeld = false;
    this.onPadChange = null;
    this._padPrev = [];
    this.hasTouch = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
    /* The first guess. `pointer: coarse` is the browser's word for "the
       main thing pointing at me is a finger", which is a better start
       than "has a touchscreen" — most laptops with one still have a
       trackpad in front of it. Corrected by whatever is used first. */
    const coarse = typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches;
    this.mode = (this.hasTouch && coarse) ? 'touch' : 'desktop';
    this.onModeChange = null;
    this._bind();
  }

  _bind() {
    addEventListener('keydown', e => {
      const a = KEYMAP[e.code];
      /* a fresh press, not the key's auto-repeat, whether or not the
         browser marks repeats */
      const fresh = !e.repeat && !this.keys.has(e.code);
      if (a) { this.keys.add(a); e.preventDefault(); if (fresh) this.latch.add(a); }
      /* raw codes too, so debug keys do not need a mapping entry */
      this.keys.add(e.code);
      if (fresh) this.latch.add(e.code);
      this.setMode('desktop');
    });
    addEventListener('keyup', e => {
      const a = KEYMAP[e.code];
      if (a) this.keys.delete(a);
      this.keys.delete(e.code);
    });
    addEventListener('blur', () => this.keys.clear());

    /* Which device is in charge: decided in the capture phase, before
       anything else sees the event, so the touch layer and the canvas
       always agree on whose turn it is. */
    addEventListener('pointerdown', e => {
      this.setMode(e.pointerType === 'mouse' ? 'desktop' : 'touch');
      /* a finger on the screen takes the controls back from the pad */
      if (e.pointerType !== 'mouse') this.setPadHeld(false);
    }, true);

    this.canvas.addEventListener('mousedown', e => {
      if (e.button === 0) this.mouseDown = true;
      /* A PRESS AND NOT A HOLD. The right button was carried for years
         and read by nothing; it steps the scope now, and a step is an
         edge — so the press is latched here and consumed in sample(),
         the same bargain the key presses make, because a click can be
         shorter than a tic. */
      if (e.button === 2) { this.mouseRight = true; this.mouseRightPulse = true; }
      if (!this.locked) this.requestLock();
    });
    addEventListener('mouseup', e => {
      if (e.button === 0) this.mouseDown = false;
      if (e.button === 2) this.mouseRight = false;
    });
    this.canvas.addEventListener('contextmenu', e => e.preventDefault());
    addEventListener('mousemove', e => {
      if (!this.locked) return;
      this.mouseDX += e.movementX || 0;
      this.mouseDY += e.movementY || 0;
    });
    addEventListener('wheel', e => { this.wheel += Math.sign(e.deltaY); }, { passive: true });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === this.canvas;
    });
  }

  setMode(mode) {
    if (mode === this.mode) return;
    this.mode = mode;
    if (mode === 'touch') {
      this.exitLock();
      this.mouseDown = this.mouseRight = false;
    } else {
      const t = this.touch;
      t.move.x = t.move.y = 0; t.attack = t.use = t.run = false;
    }
    this.onModeChange?.(mode);
  }

  setPadHeld(on) {
    if (on === this.padHeld) return;
    this.padHeld = on;
    this.onPadChange?.(on);
  }

  requestLock() {
    if (this.mode === 'touch' || !this.canvas.requestPointerLock) return;
    /* newer browsers hand back a promise that rejects when the lock is
       refused, and an unhandled rejection is not a way to say no */
    let p;
    try { p = this.canvas.requestPointerLock(); } catch (e) { return; }
    if (p && typeof p.catch === 'function') p.catch(() => {});
  }

  exitLock() {
    if (document.pointerLockElement && document.exitPointerLock) document.exitPointerLock();
  }

  down(name) { return this.keys.has(name); }
  pressed(name) { return this.latch.has(name) || (this.keys.has(name) && !this.prev.has(name)); }

  /** Call once a frame, before anything reads it. */
  sample(dt) {
    const pad = this._gamepad();

    /* THE PAD, THE WAY EVERY SHOOTER LAYS IT OUT, at the user's request:
       the LEFT stick moves and the RIGHT stick looks. The triggers are
       the trigger: R2 fires, L2 jumps; the bumpers cycle the weapons,
       L1 back and R1 forward; A is use and either stick pressed in is
       run. */
    const btn = i => !!(pad && pad.buttons[i]?.pressed);
    const padEdge = i => { const now = btn(i), was = !!this._padPrev[i]; this._padPrev[i] = now; return now && !was; };

    let mx = 0, my = 0;
    if (this.down('right')) mx += 1;
    if (this.down('left')) mx -= 1;
    if (this.down('forward')) my += 1;
    if (this.down('back')) my -= 1;
    if (pad) { mx += dead(pad.axes[0]); my -= dead(pad.axes[1]); }
    mx += this.touch.move.x; my += this.touch.move.y;

    const mag = Math.hypot(mx, my);
    if (mag > 1) { mx /= mag; my /= mag; }
    this.move = { x: mx, y: my };

    let lx = this.mouseDX * this.sensitivity;
    let ly = this.mouseDY * this.sensitivity;
    this.mouseDX = 0; this.mouseDY = 0;

    /* Keyboard turning and the right stick are RATES, so they scale with
       the frame; the mouse and a thumb are displacements and must not. */
    const turn = 2.6 * dt;
    if (this.down('turnLeft')) lx -= turn;
    if (this.down('turnRight')) lx += turn;
    if (pad) {
      lx += dead(pad.axes[2]) * 3.2 * dt;
      ly += dead(pad.axes[3]) * 2.2 * dt;
    }
    lx += this.touch.look.x; ly += this.touch.look.y;
    this.touch.look.x = 0; this.touch.look.y = 0;
    if (this.invertY) ly = -ly;
    /* A ZOOMED PICTURE TURNS SLOWER, by exactly as much as it is zoomed.
       js/main.js sets this off the scope's step (see VIEW_ZOOM in
       js/scope.js); it is 1 the rest of the time and this line does
       nothing. Without it, a narrowed field of view is a mouse that has
       become twice as twitchy at the moment you were trying to be
       careful, which is the opposite of what a scope is for. */
    const zs = this.zoomScale ?? 1;
    this.look = { x: lx * zs, y: ly * zs };

    this.attack = this.mouseDown || this.down('attack') || this.touch.attack || btn(7);
    /* a tap shorter than a tic still counts as one press of Use */
    this.use = this.down('use') || this.touch.use || this.touch.usePulse || btn(0);
    this.touch.usePulse = false;
    this.run = this.down('run') || this.touch.run || btn(10) || btn(11);
    /* JUMP is a press, not a hold: one jump per press of the key, the
       trigger or the button, so holding it down is not a pogo stick */
    /* the pad edge first, for the reason given at the zoom below: an ||
       that short-circuits past padEdge leaves its record a frame stale
       and swallows the next press off the pad */
    const padJump = padEdge(6);
    this.jump = this.pressed('jump') || this.touch.jumpPulse || padJump;
    this.touch.jumpPulse = false;

    this.weaponSlot = 0;
    if (this.pressed('weapon1')) this.weaponSlot = 1;
    if (this.pressed('weapon2')) this.weaponSlot = 2;
    if (this.pressed('weapon3')) this.weaponSlot = 3;
    if (this.pressed('weapon4')) this.weaponSlot = 4;
    if (this.pressed('weapon5')) this.weaponSlot = 5;
    if (this.pressed('weapon6')) this.weaponSlot = 6;
    if (this.pressed('weapon7')) this.weaponSlot = 7;
    if (this.touch.weapon) { this.weaponSlot = this.touch.weapon; this.touch.weapon = 0; }
    this.weaponCycle = this.wheel; this.wheel = 0;
    if (this.touch.cycle) { this.weaponCycle = this.touch.cycle; this.touch.cycle = 0; }
    if (padEdge(4)) this.weaponCycle = -1;
    if (padEdge(5)) this.weaponCycle = 1;

    /* and whether the pad said anything at all this frame, which is
       what fades the thumb controls off the picture — see padHeld */
    if (pad) {
      let used = false;
      for (let i = 0; i < 4 && !used; i++) if (dead(pad.axes[i])) used = true;
      for (let i = 0; i < pad.buttons.length && !used; i++) if (pad.buttons[i]?.pressed) used = true;
      if (used) this.setPadHeld(true);
    }

    /* THE SCOPE STEPS ON A PRESS: the right button, Z or C, the pad's B.
       One edge per press, whichever of the four it came from.

       THE PAD EDGE IS TAKEN FIRST AND NOT LAST, because padEdge has a
       side effect — it records what the button was doing this frame —
       and an || that short-circuits past it leaves that record a frame
       stale, so the next press off the pad is swallowed. Pressing Z
       while resting a thumb on B was enough to do it. */
    /* THE PHONE HAS TWO, at the user's request: AIM, which puts the gun
       up and takes it down, and the magnification, which is only on the
       glass while it is up and steps between the aimed steps — see
       Scope.toggleAim and Scope.stepAimed.

       AND ALL THREE ARE KEPT UNTIL THEY ARE TAKEN. This runs once a
       tic and js/main.js reads them once a FRAME, and the two clocks are
       not the same clock: at sixty frames a second four frames in ten
       have no tic in them, and a flag that was simply left standing
       stepped the scope twice for one press about as often as that —
       and a toggle that goes up and straight back down is a button that
       does nothing. So they are set here and cleared by the one reader
       (takeScope), and a press can no more be counted twice than lost. */
    const padZoom = padEdge(1);
    if (this.pressed('zoom') || this.mouseRightPulse || padZoom) this.zoomPressed = true;
    if (this.touch.zoomPulse) this.zoomStep = true;
    if (this.touch.aimPulse) this.aimToggle = true;
    this.mouseRightPulse = false;
    this.touch.zoomPulse = false;
    this.touch.aimPulse = false;

    /* AND THE PAUSE MENU OPENS ON START, at the user's request, which it
       did not: pausing was Escape or P and nothing else, so a player on
       a pad had no way into the menu at all and the button already
       sitting in the page for a player on a phone — .tb-pause, in
       index.html since the touch controls were built — was wired to
       nothing on the way in. Both go through the one flag the game
       reads, and it is read on both sides of the pause: see Game.update,
       which keeps sampling while stopped, because a pause that stops
       listening for the pause button is a door with no handle on the
       inside.

       BOTH OF THE PAD'S MIDDLE BUTTONS, not just the one. Nine is Start
       in the standard mapping and eight is Select — Options and Share,
       Menu and View, +/- — and which of the two a player reaches for is
       a matter of what console they grew up with. Neither does anything
       else in this game. */
    const padStart = padEdge(9), padSelect = padEdge(8);
    this.pausePressed = this.pressed('pause') || this.touch.pausePulse || padStart || padSelect;
    this.touch.pausePulse = false;
    this.mapPressed = this.pressed('map');

    this.prev = new Set(this.keys);
    this.latch.clear();
  }

  /** THE SCOPE'S PRESSES, TAKEN: once a frame, by js/main.js, the one
   *  thing that works a sight — see Scope.work. Which came in since the
   *  last time, 'aim', 'step' or 'cycle', or null, and all three are
   *  cleared either way. A word and not an object, because this is asked
   *  every frame and the answer is almost always no. */
  takeScope() {
    const press = this.aimToggle ? 'aim' : this.zoomStep ? 'step' : this.zoomPressed ? 'cycle' : null;
    this.aimToggle = this.zoomStep = this.zoomPressed = false;
    return press;
  }

  _gamepad() {
    if (!navigator.getGamepads) return null;
    const pads = navigator.getGamepads();
    for (const p of pads) if (p && p.connected) return p;
    return null;
  }
}

const dead = v => (Math.abs(v || 0) < 0.18 ? 0 : v);
