import matplotlib.pyplot as plt
from matplotlib.widgets import TextBox, Button
import numpy as np
import sys
import subprocess

# ⚠️ CHANGE THIS TO YOUR ACTUAL DEVICE NAME from `hyprctl devices`
DEVICE_NAME = "logitech-g502-x-ls-1"

class DraggableAccelCurve:
    def __init__(self, initial_string):
        self.fig, (self.ax1, self.ax2) = plt.subplots(2, 1, figsize=(12, 9))
        self.fig.canvas.manager.set_window_title('Hyprland Libinput Curve Tuner (Two-Way)')
        self.fig.subplots_adjust(bottom=0.25, hspace=0.3)

        self.parse_string(initial_string)

        # Plot 1: Raw points (ax1)
        self.ax1.set_title("Libinput Raw Points (y = M * x) - Drag cyan dots")
        self.ax1.set_xlabel("Device Speed (x)")
        self.ax1.set_ylabel("Target Pointer Speed (y)")
        self.ax1.grid(True, linestyle='--', alpha=0.7)
        self.line, = self.ax1.plot(self.x, self.y, marker='o', markersize=8, color='cyan', markeredgecolor='blue', linestyle='-', linewidth=2)

        # Plot 2: Multiplier (ax2) - Now Draggable
        self.ax2.set_title("Actual Acceleration Multiplier (Drag magenta squares to edit feel)")
        self.ax2.set_xlabel("Device Speed (x)")
        self.ax2.set_ylabel("Multiplier (M)")
        self.ax2.grid(True, linestyle='--', alpha=0.7)

        # Initial multiplier calc (skip index 0, x=0 has no multiplier)
        self.mults = [self.y[i]/self.x[i] if self.x[i] != 0 else 0 for i in range(1, len(self.x))]
        self.mult_line, = self.ax2.plot(self.x[1:], self.mults, marker='s', markersize=8, color='magenta', markeredgecolor='purple', linestyle='-', linewidth=2)

        self.active_idx = None
        self.active_axis = None

        # UI Elements
        ax_box = self.fig.add_axes([0.15, 0.1, 0.6, 0.05])
        self.text_box = TextBox(ax_box, 'String:', initial=self.get_string())
        self.text_box.on_submit(self.on_text_submit)

        ax_btn = self.fig.add_axes([0.8, 0.1, 0.1, 0.05])
        self.btn = Button(ax_btn, 'Apply Live')
        self.btn.on_clicked(self.apply_hyprctl)

        self.fig.canvas.mpl_connect('button_press_event', self.on_press)
        self.fig.canvas.mpl_connect('button_release_event', self.on_release)
        self.fig.canvas.mpl_connect('motion_notify_event', self.on_motion)

        plt.show()

    def parse_string(self, s):
        try:
            parts = s.split()
            self.step = float(parts[1])
            self.y = [float(p) for p in parts[2:]]
            self.x = [i * self.step for i in range(len(self.y))]
        except Exception as e:
            print(f"Error parsing string: {e}")

    def get_string(self):
        pts = " ".join([f"{val:.3f}" for val in self.y])
        return f"custom {self.step} {pts}"

    def update_plots(self):
        # Update raw points graph
        self.line.set_xdata(self.x)
        self.line.set_ydata(self.y)

        # Recalculate and update multiplier graph
        self.mults = [self.y[i]/self.x[i] if self.x[i] != 0 else 0 for i in range(1, len(self.x))]
        self.mult_line.set_xdata(self.x[1:])
        self.mult_line.set_ydata(self.mults)

        self.ax1.relim()
        self.ax1.autoscale_view()
        self.ax2.relim()
        self.ax2.autoscale_view()

        self.fig.canvas.draw_idle()

    def on_text_submit(self, text):
        self.parse_string(text)
        self.text_box.set_val(self.get_string())
        self.update_plots()

    def apply_hyprctl(self, event):
        cmd = f'hyprctl keyword "device[{DEVICE_NAME}]:accel_profile" "{self.get_string()}"'
        print(f"Applying: {cmd}")
        subprocess.run(cmd, shell=True)

    def on_press(self, event):
        if event.inaxes == self.ax1:
            pts = self.ax1.transData.transform(np.c_[self.x, self.y])
            clk = np.array([event.x, event.y])
            dists = np.linalg.norm(pts - clk, axis=1)
            if np.min(dists) < 15:
                self.active_idx = np.argmin(dists)
                self.active_axis = 'ax1'
        elif event.inaxes == self.ax2:
            pts = self.ax2.transData.transform(np.c_[self.x[1:], self.mults])
            clk = np.array([event.x, event.y])
            dists = np.linalg.norm(pts - clk, axis=1)
            if np.min(dists) < 15:
                # +1 because the multiplier array skips index 0
                self.active_idx = np.argmin(dists) + 1
                self.active_axis = 'ax2'

    def on_motion(self, event):
        if self.active_idx is None: return

        if self.active_axis == 'ax1' and event.inaxes == self.ax1:
            # User is dragging raw libinput points
            new_y = max(0.0, event.ydata)
            self.y[self.active_idx] = new_y

        elif self.active_axis == 'ax2' and event.inaxes == self.ax2:
            # User is dragging the multiplier; calculate required raw y
            new_mult = max(0.0, event.ydata)
            self.y[self.active_idx] = new_mult * self.x[self.active_idx]

        self.text_box.set_val(self.get_string())
        self.update_plots()

    def on_release(self, event):
        self.active_idx = None
        self.active_axis = None

if __name__ == '__main__':
    # Starting string with a proper linear baseline to avoid deadzones
    test_string = "custom 0.1 0.0 0.1 0.21 0.33 0.46 0.6 0.744 0.896 1.056 1.224 1.4 1.584 1.776 1.976 2.184 2.4 2.624 2.856 3.096 3.344 3.6 3.864 4.136 4.416 4.704 5.0 5.2"
    if len(sys.argv) > 1:
        test_string = sys.argv[1]
    DraggableAccelCurve(test_string)
