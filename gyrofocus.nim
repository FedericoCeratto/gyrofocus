
from os import execShellCmd, sleep
from times import getTime, toSeconds
import json
import parseopt
import posix
import strutils
import terminal

const
  acc_phi = 0.005
  conf_fname = "gyrofocus.json"

type
  Vector = tuple[x, y, z: float]

proc `*`(self: Vector, a: float): Vector =
  result = (self.x * a, self.y * a, self.z * a)

proc `*`(self, other: Vector): float =
  # dot product
  result = self.x * other.x + self.y * other.y + self.z * other.z

proc `+`(self, other: Vector): Vector =
  result = (self.x + other.x, self.y + other.y, self.z + other.z)

proc abs(self: Vector): Vector =
  # return a Vector built using abs() on each coordinate
  result = (abs(self.x), abs(self.y), abs(self.z))

proc max(self: Vector): float =
  # return the value of the maximum coord
  result = max(self.x, self.y, self.z)


proc configure_ttyUSB(fn: string): int {.discardable.} =
  echo "Configuring serial port ", fn
  return execShellCmd("stty -F $1 cs8 115200 ignbrk -brkint -icrnl -imaxbel -opost -onlcr -isig -icanon -iexten -echo -echoe -echok -echoctl -echoke noflsh -ixon -crtscts" % [fn])

proc print_bar(scaled: int, marker='|'): void =
  if scaled >= 0:
    echo ' '.repeat(40), marker, '*'.repeat(scaled)

  else:
    echo ' '.repeat(40+scaled), '*'.repeat(-scaled), marker

proc readVector(f: File): Vector =
    let line = f.readline()
    let omega_seq = map(line.split, parseFloat)
    result = (omega_seq[0], omega_seq[1], omega_seq[2])

proc calibrate(f: File): void =
  var omega, alpha: Vector
  let t = getTime().toSeconds

  echo """Start the application while looking on the left and then move to the right and wait.
calibrating...



"""

  while true:
    if getTime().toSeconds > t + 5:
      break

    try:
      omega = readVector(f)
    except:
      continue

    cursorUp()
    eraseLine()
    cursorUp()
    eraseLine()
    cursorUp()
    eraseLine()

    alpha = alpha + omega
    let scaled = alpha * (1/90000)
    print_bar(int(scaled.x), 'X')
    print_bar(int(scaled.y), 'Y')
    print_bar(int(scaled.z), 'Z')

  let m = alpha.abs.max

  echo "Done."
  echo "Max value (useful to decide the threshold in gyrofocus.json): ", m
  echo "x: ", formatFloat(alpha[0]/m, precision=3)
  echo "y: ", formatFloat(alpha[1]/m, precision=3)
  echo "z: ", formatFloat(alpha[2]/m, precision=3)

  quit()


proc main() =
  let
    conf = parseFile(conf_fname)
    lr_thresh = conf["threshold"].getFNum
    orientation_coeff: Vector = (conf["xcoeff"].getFNum, conf["ycoeff"].getFNum, conf["zcoeff"].getFNum)
    ttyname = conf["ttyname"].str
    focus_left_cmd = conf["focus_left_cmd"].str
    focus_right_cmd = conf["focus_right_cmd"].str

  var
    omega, accumulator: Vector
    debug = false
    show_bar = false
    t = getTime().toSeconds
    samples_cnt = 0

  for kind, key, val in getopt():
    if kind == cmdShortOption and key == "c":
      let f = open(ttyname, fmRead)
      calibrate(f)
      quit()
    elif kind == cmdShortOption and key == "d":
      debug = true
    elif kind == cmdShortOption and key == "b":
      show_bar = true
    elif kind == cmdShortOption and key == "h":
      echo """Help:
      c: calibrate
      d: debug
      b: show movement bar
      """
      quit()

  configure_ttyUSB(ttyname)
  let f = open(ttyname, fmRead)

  echo "starting..."
  while true:

    try:
      omega = readVector(f)
    except:
      continue

    if debug:
      samples_cnt += 1
      if t != getTime().toSeconds:
        t = getTime().toSeconds
        echo "Samples per second: ", samples_cnt
        samples_cnt = 0

    accumulator = omega * acc_phi + accumulator * (1 - acc_phi)

    var orientation_val = orientation_coeff * accumulator

    if show_bar:
      var scaled = int(orientation_val * 10 / lr_thresh)
      eraseLine()
      print_bar(scaled)
      cursorUp()

    if orientation_val > lr_thresh:
        discard execShellCmd(focus_right_cmd)
        accumulator = (0.0, 0.0, 0.0)

    elif orientation_val < -lr_thresh:
        discard execShellCmd(focus_left_cmd)
        accumulator = (0.0, 0.0, 0.0)


when isMainModule:
  main()
