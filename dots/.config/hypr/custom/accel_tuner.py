import matplotlib.pyplot as plt
from matplotlib.widgets import TextBox, Button
from scipy.interpolate import pchip_interpolate
import numpy as np
import sys
import subprocess
import time

# ⚠️ CHANGE THIS TO YOUR ACTUAL DEVICE NAME from `hyprctl devices`
DEVICE_NAME = "logitech-g502-x-ls-1"

class DraggableAccelCurve:
    def __init__(self):
        self.fig, (self.ax1, self.ax2) = plt.subplots(2, 1, figsize=(12, 9))
        self.fig.canvas.manager.set_window_title('Hyprland Libinput PCHIP Tuner')
        self.fig.subplots_adjust(bottom=0.25, hspace=0.3)
        self.fig.patch.set_facecolor('#1e1e2e') # dark mode bg

        # --- Data Setup ---
        self.step = 0.1
        self.max_x = 5.2 # How far the libinput array goes
        self.libinput_x = np.arange(0, self.max_x + self.step, self.step)

        # Default Control Points for Multiplier (x, y)
        self.ctrl_x = np.array([0.1, 0.5, 1.0, 2.0, 5.2])
        self.ctrl_y = np.array([0.5, 0.5, 1.6, 1.8, 2.0])

        # --- Plot 1: Raw points (ax1) ---
        self.ax1.set_facecolor('#11111b')
        self.ax1.set_title("Libinput Raw Points (Sampled from curve below)", color='white')
        self.ax1.tick_params(colors='white')
        self.ax1.grid(True, linestyle='--', alpha=0.3)

        # The generated libinput points
        self.raw_line, = self.ax1.plot([], [], marker='.', color='cyan', linestyle='-', linewidth=1)
        # Velocity Tracker line
        self.tracker_line1 = self.ax1.axvline(x=0, color='yellow', alpha=0.8, linewidth=2)

        # --- Plot 2: Multiplier (ax2) - The Editable Area ---
        self.ax2.set_facecolor('#11111b')
        self.ax2.set_title("Multiplier Control Curve (Drag Magenta Squares)", color='white')
        self.ax2.set_xlabel("Device Speed (x)", color='white')
        self.ax2.tick_params(colors='white')
        self.ax2.grid(True, linestyle='--', alpha=0.3)
        self.ax2.set_xlim(0, 5.5)
        self.ax2.set_ylim(0, 3.0)

        # The Smooth Interpolated Curve
        self.smooth_line, = self.ax2.plot([], [], color='magenta', linewidth=2, alpha=0.7)
        # The Draggable Control Points
        self.ctrl_points_plot, = self.ax2.plot(self.ctrl_x, self.ctrl_y, marker='s', markersize=10,
                                               color='magenta', markeredgecolor='white', linestyle='None')
        # Velocity Tracker line
        self.tracker_line2 = self.ax2.axvline(x=0, color='yellow', alpha=0.8, linewidth=2)

        # --- State Variables ---
        self.active_idx = None
        self.last_mouse_time = time.time()
        self.last_mouse_pos = None
        self.smooth_velocity = 0.0

        # --- UI Elements ---
        ax_box = self.fig.add_axes([0.15, 0.1, 0.6, 0.05])
        self.text_box = TextBox(ax_box, 'String:', initial="")

        ax_btn = self.fig.add_axes([0.8, 0.1, 0.1, 0.05])
        self.btn = Button(ax_btn, 'Apply Live')
        self.btn.on_clicked(self.apply_hyprctl)

        self.fig.canvas.mpl_connect('button_press_event', self.on_press)
        self.fig.canvas.mpl_connect('button_release_event', self.on_release)
        self.fig.canvas.mpl_connect('motion_notify_event', self.on_motion)

        self.update_math()
        plt.show()

    def update_math(self):
        # Sort control points by X to prevent spline mathematical errors
        sort_idx = np.argsort(self.ctrl_x)
        sorted_x = self.ctrl_x[sort_idx]
        sorted_y = self.ctrl_y[sort_idx]

        # 1. Generate high-res smooth curve for the bottom graph
        dense_x = np.linspace(sorted_x[0], sorted_x[-1], 200)
        dense_y = pchip_interpolate(sorted_x, sorted_y, dense_x)

        self.smooth_line.set_xdata(dense_x)
        self.smooth_line.set_ydata(dense_y)
        self.ctrl_points_plot.set_xdata(self.ctrl_x)
        self.ctrl_points_plot.set_ydata(self.ctrl_y)

        # 2. Sample the spline at libinput step intervals
        # Handle values outside the control points by extending the first/last values
        sampled_mults = np.interp(self.libinput_x, dense_x, dense_y)

        # 3. Calculate libinput raw y = M * x
        self.libinput_y = sampled_mults * self.libinput_x
        self.raw_line.set_xdata(self.libinput_x)
        self.raw_line.set_ydata(self.libinput_y)

        # Update text string
        pts = " ".join([f"{val:.3f}" for val in self.libinput_y])
        self.current_string = f"custom {self.step} {pts}"
        self.text_box.set_val(self.current_string)

        # Only autoscale the top graph occasionally to prevent lag
        self.ax1.relim()
        self.ax1.autoscale_view()
        self.fig.canvas.draw_idle()

    def apply_hyprctl(self, event):
        cmd = f'hyprctl keyword "device[{DEVICE_NAME}]:accel_profile" "{self.current_string}"'
        print(f"Applying: {cmd}")
        subprocess.run(cmd, shell=True)

    def on_press(self, event):
        if event.inaxes != self.ax2: return
        # Find closest control point
        pts = self.ax2.transData.transform(np.c_[self.ctrl_x, self.ctrl_y])
        clk = np.array([event.x, event.y])
        dists = np.linalg.norm(pts - clk, axis=1)
        if np.min(dists) < 15:
            self.active_idx = np.argmin(dists)

    def on_motion(self, event):
        # --- Velocity Tracker Logic ---
        current_time = time.time()
        if self.last_mouse_pos is not None and event.x is not None:
            dt = current_time - self.last_mouse_time
            if dt > 0.01: # Cap update rate
                dist = np.hypot(event.x - self.last_mouse_pos[0], event.y - self.last_mouse_pos[1])
                raw_vel = (dist / dt) / 1000.0 # Arbitrary scaling factor to map pixels/sec to libinput X axis
                # Smooth the velocity for readability
                self.smooth_velocity = 0.7 * self.smooth_velocity + 0.3 * raw_vel

                self.tracker_line1.set_xdata([self.smooth_velocity, self.smooth_velocity])
                self.tracker_line2.set_xdata([self.smooth_velocity, self.smooth_velocity])
                self.last_mouse_time = current_time
                self.last_mouse_pos = (event.x, event.y)
                self.fig.canvas.draw_idle()
        else:
            if event.x is not None:
                self.last_mouse_pos = (event.x, event.y)

        # --- Drag Logic ---
        if self.active_idx is None or event.inaxes != self.ax2: return

        # Constrain X so points don't cross each other easily, and keep Y positive
        new_x = max(0.01, min(self.max_x, event.xdata))
        new_y = max(0.0, event.ydata)

        self.ctrl_x[self.active_idx] = new_x
        self.ctrl_y[self.active_idx] = new_y

        # Update graphics WITHOUT calling ax.relim() to keep it silky smooth
        self.update_math()

    def on_release(self, event):
        self.active_idx = None

if __name__ == '__main__':
    DraggableAccelCurve()
