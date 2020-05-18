#include "workspace.h"

extern struct event_loop g_event_loop;

void workspace_event_handler_init(void **context)
{
    workspace_context *ws_context = [workspace_context alloc];
    *context = ws_context;
}

void workspace_event_handler_begin(void **context)
{
    workspace_context *ws_context = *context;
    [ws_context init];
}

void workspace_event_handler_end(void *context)
{
    workspace_context *ws_context = (workspace_context *) context;
    [ws_context dealloc];
}

void workspace_application_observe_finished_launching(void *context, void *process)
{
    workspace_context *ws_context = (workspace_context *) context;

    NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:((struct process *)process)->pid];

    [application addObserver:ws_context
                forKeyPath:@"finishedLaunching"
                options:NSKeyValueObservingOptionNew
                context:process];
}

void workspace_application_observe_activation_policy(void *context, void *process)
{
    workspace_context *ws_context = (workspace_context *) context;

    NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:((struct process *)process)->pid];

    [application addObserver:ws_context
                forKeyPath:@"activationPolicy"
                options:NSKeyValueObservingOptionNew
                context:process];
}

bool workspace_application_is_observable(pid_t pid)
{
    NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    bool result = [application activationPolicy] != NSApplicationActivationPolicyProhibited;
    [application release];
    return result;
}

bool workspace_application_is_finished_launching(pid_t pid)
{
    NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    bool result = [application isFinishedLaunching] == YES;
    [application release];
    return result;
}

@implementation workspace_context
- (id)init
{
    if ((self = [super init])) {
       [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                selector:@selector(activeDisplayDidChange:)
                name:@"NSWorkspaceActiveDisplayDidChangeNotification"
                object:nil];

       [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                selector:@selector(activeSpaceDidChange:)
                name:NSWorkspaceActiveSpaceDidChangeNotification
                object:nil];

       [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                selector:@selector(didHideApplication:)
                name:NSWorkspaceDidHideApplicationNotification
                object:nil];

       [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                selector:@selector(didUnhideApplication:)
                name:NSWorkspaceDidUnhideApplicationNotification
                object:nil];

       [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                selector:@selector(didWake:)
                name:NSWorkspaceDidWakeNotification
                object:nil];

       [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(didRestartDock:)
                name:@"NSApplicationDockDidRestartNotification"
                object:nil];

       [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                selector:@selector(didChangeMenuBarHiding:)
                name:@"AppleInterfaceMenuBarHidingChangedNotification"
                object:nil];

       [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                selector:@selector(didChangeDockPref:)
                name:@"com.apple.dock.prefchanged"
                object:nil];
    }

    return self;
}

- (void)dealloc
{
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"activationPolicy"]) {
        int policy = (int) [change objectForKey:NSKeyValueChangeNewKey];
        if (policy != NSApplicationActivationPolicyProhibited) {
            struct process *process = context;

            debug("%s: activation policy changed for %s\n", __FUNCTION__, process->name);
            struct event *event = event_create(&g_event_loop, APPLICATION_LAUNCHED, process);
            event_loop_post(&g_event_loop, event);

            [object removeObserver:self forKeyPath:@"activationPolicy"];
            [object release];
        }
    }

    if ([keyPath isEqualToString:@"finishedLaunching"]) {
        bool result = [change objectForKey:NSKeyValueChangeNewKey];
        if (result) {
            struct process *process = context;

            debug("%s: %s finished launching\n", __FUNCTION__, process->name);
            struct event *event = event_create(&g_event_loop, APPLICATION_LAUNCHED, process);
            event_loop_post(&g_event_loop, event);

            [object removeObserver:self forKeyPath:@"finishedLaunching"];
            [object release];
        }
    }
}

- (void)didWake:(NSNotification *)notification
{
    struct event *event = event_create(&g_event_loop, SYSTEM_WOKE, NULL);
    event_loop_post(&g_event_loop, event);
}

- (void)didRestartDock:(NSNotification *)notification
{
    struct event *event = event_create(&g_event_loop, DOCK_DID_RESTART, NULL);
    event_loop_post(&g_event_loop, event);
}

- (void)didChangeMenuBarHiding:(NSNotification *)notification
{
    struct event *event = event_create(&g_event_loop, MENU_BAR_HIDDEN_CHANGED, NULL);
    event_loop_post(&g_event_loop, event);
}

- (void)didChangeDockPref:(NSNotification *)notification
{
    struct event *event = event_create(&g_event_loop, DOCK_DID_CHANGE_PREF, NULL);
    event_loop_post(&g_event_loop, event);
}

- (void)activeDisplayDidChange:(NSNotification *)notification
{
    struct event *event = event_create(&g_event_loop, DISPLAY_CHANGED, NULL);
    event_loop_post(&g_event_loop, event);
}

- (void)activeSpaceDidChange:(NSNotification *)notification
{
    struct event *event = event_create(&g_event_loop, SPACE_CHANGED, NULL);
    event_loop_post(&g_event_loop, event);
}

- (void)didHideApplication:(NSNotification *)notification
{
    pid_t pid = [[notification.userInfo objectForKey:NSWorkspaceApplicationKey] processIdentifier];
    struct event *event = event_create(&g_event_loop, APPLICATION_HIDDEN, (void *)(intptr_t) pid);
    event_loop_post(&g_event_loop, event);
}

- (void)didUnhideApplication:(NSNotification *)notification
{
    pid_t pid = [[notification.userInfo objectForKey:NSWorkspaceApplicationKey] processIdentifier];
    struct event *event = event_create(&g_event_loop, APPLICATION_VISIBLE, (void *)(intptr_t) pid);
    event_loop_post(&g_event_loop, event);
}

@end
