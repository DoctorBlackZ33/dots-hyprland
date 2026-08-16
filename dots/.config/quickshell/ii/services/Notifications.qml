pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 *  - History culling and limits (dynamic-rice override)
 */
Singleton {
	id: root

	function notificationSourceDevice(notification) {
		const hints = notification?.hints;
		if (!hints) return "";

		const sourceDevice = hints["x-kdeconnect-source-device"];
		return sourceDevice === undefined || sourceDevice === null ? "" : String(sourceDevice);
	}

    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property string sourceDevice: ""
        property string groupKey: appName === "KDE Connect" && sourceDevice.length > 0
            ? `${appName} · ${sourceDevice}`
            : appName
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification !== null) {
                sourceDevice = root.notificationSourceDevice(notification);
            } else {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "sourceDevice": notif.sourceDevice,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            if (notifObject?.isTransient) root.discardNotification(notificationId);
            else if (notifObject) root.timeoutNotification(notificationId);
            if (notifObject) notifObject.timer = null;
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }

    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            const groupKey = notif.groupKey || notif.appName;
            if (!root.latestTimeForApp[groupKey] || notif.time > root.latestTimeForApp[groupKey]) {
                root.latestTimeForApp[groupKey] = Math.max(root.latestTimeForApp[groupKey] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((groupKey) => {
            if (!root.list.some((notif) => (notif.groupKey || notif.appName) === groupKey)) {
                delete root.latestTimeForApp[groupKey];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            const groupKey = notif.groupKey || notif.appName;
            if (!groups[groupKey]) {
                groups[groupKey] = {
                    appName: groupKey,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[groupKey].notifications.push(notif);
            // Always set to the latest time in the group
            groups[groupKey].time = latestTimeForApp[groupKey] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            notification.tracked = true
            const notificationId = notification.id + root.idOffset;
            let notifObject = root.list.find((notif) => notif.notificationId === notificationId);
            const isUpdate = notifObject !== undefined;

            if (isUpdate) {
                notifObject.notification = notification;
                notifObject.sourceDevice = root.notificationSourceDevice(notification);
                notifObject.time = Date.now();
            } else {
                notifObject = notifComponent.createObject(root, {
                    "notificationId": notificationId,
                    "notification": notification,
                    "sourceDevice": root.notificationSourceDevice(notification),
                    "time": Date.now(),
                });
				root.list = [...root.list, notifObject];
            }

            root.configurePopup(notifObject, notification);
            if (!root.popupInhibited && !isUpdate) root.unread++;
            if (isUpdate) root.triggerListChange();
            root.notify(notifObject);
            // Apply history limit after adding
            root.applyHistoryLimit();
            // Persist
            notifFileView.setText(stringifyList(root.list));
        }
    }

    function clearTimer(notifObject) {
        if (!notifObject?.timer) return;
        notifObject.timer.stop();
        notifObject.timer.destroy();
        notifObject.timer = null;
    }

    function configurePopup(notifObject, notification) {
        clearTimer(notifObject);

        if (root.popupInhibited) {
            notifObject.popup = false;
            return;
        }

        notifObject.popup = true;
        if (notification.expireTimeout != 0) {
            const timeoutMs = notification.expireTimeout < 0
                ? (Config?.options.notifications.timeout ?? 10000)
                : notification.expireTimeout;
            notifObject.timer = notifTimerComponent.createObject(root, {
                "notificationId": notifObject.notificationId,
                "interval": timeoutMs,
            });
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    // Batch discard: collects IDs to discard, then writes file once
    property var pendingDiscardIds: []
    property var pendingDiscardServerIds: []
    Timer {
        id: batchDiscardTimer
        interval: 50
        running: false
        onTriggered: {
            if (root.pendingDiscardIds.length === 0) return;
            const ids = root.pendingDiscardIds.slice();
            const serverIds = root.pendingDiscardServerIds.slice();
            root.pendingDiscardIds = [];
            root.pendingDiscardServerIds = [];

            // Remove all at once from list
            const idSet = new Set(ids);
            root.list = root.list.filter((notif) => !idSet.has(notif.notificationId));

            // Dismiss from server
            serverIds.forEach((serverIndex) => {
                if (serverIndex !== -1 && notifServer.trackedNotifications.values[serverIndex]) {
                    notifServer.trackedNotifications.values[serverIndex].dismiss();
                }
            });

            // Single file write
            notifFileView.setText(stringifyList(root.list));
            triggerListChange();

            // Emit discard signals
            ids.forEach((id) => root.discard(id));
        }
    }

    function discardNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);

        if (index !== -1) {
            // Use batch discard for performance
            root.pendingDiscardIds.push(id);
            root.pendingDiscardServerIds.push(notifServerIndex);
            if (!batchDiscardTimer.running) batchDiscardTimer.start();
        }
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    // Discard all notifications from a specific app (batched)
    function discardNotificationsByApp(appName) {
        const ids = [];
        const serverIds = [];
        root.list = root.list.filter((notif) => {
            if ((notif.groupKey || notif.appName) === appName) {
                ids.push(notif.notificationId);
                const serverIndex = notifServer.trackedNotifications.values.findIndex((n) => n.id + root.idOffset === notif.notificationId);
                serverIds.push(serverIndex);
                return false;
            }
            return true;
        });

        serverIds.forEach((serverIndex) => {
            if (serverIndex !== -1 && notifServer.trackedNotifications.values[serverIndex]) {
                notifServer.trackedNotifications.values[serverIndex].dismiss();
            }
        });

        notifFileView.setText(stringifyList(root.list));
        triggerListChange();
        ids.forEach((id) => root.discard(id));
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index]?.timer)
            root.list[index].timer.stop();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            action.invoke()
        }
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    // Enforce max history limit by dropping oldest notifications
    function applyHistoryLimit() {
        const maxHistory = Config?.options.notifications.maxHistory ?? 100;
        if (root.list.length <= maxHistory) return;

        // Sort by time ascending (oldest first) and drop excess
        const sorted = root.list.slice().sort((a, b) => a.time - b.time);
        const toDrop = sorted.slice(0, root.list.length - maxHistory);
        const dropIds = new Set(toDrop.map(n => n.notificationId));
        root.list = root.list.filter((notif) => !dropIds.has(notif.notificationId));
    }

    // Cull old notifications on startup
    function cullOldNotifications() {
        const maxAgeHours = Config?.options.notifications.maxAgeHours ?? 24;
        const cutoff = Date.now() - (maxAgeHours * 60 * 60 * 1000);
        const before = root.list.length;
        root.list = root.list.filter((notif) => notif.time > cutoff);
        if (before !== root.list.length) {
            console.log("[Notifications] Culled " + (before - root.list.length) + " notifications older than " + maxAgeHours + "h");
            notifFileView.setText(stringifyList(root.list));
        }
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            const fileContents = notifFileView.text()
            root.list = JSON.parse(fileContents).map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": notif.image,
                    "summary": notif.summary,
                    "sourceDevice": notif.sourceDevice ?? "",
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            });
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId

            // Apply culling and limits on startup
            root.cullOldNotifications();
            root.applyHistoryLimit();

            root.initDone()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.error("[Notifications] Failed to load notifications file: " + error)
            }
            root.idOffset = 0
            root.initDone()
        }
    }
}
