// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

package mobile

import (
	"errors"

	"git.ole-hartwig.eu/development/s3mail/s3mail/go/awsx"
	"git.ole-hartwig.eu/development/s3mail/s3mail/go/core"
)

// Push registration, from the phone.
//
// Thin, like the rest of this package: the decision is in core/push.go, the
// SDK calls are in awsx/push.go, and what happens here is unwrapping the setup
// and handing the pieces over.

// RegisterForPush registers this device and subscribes it to the mailbox's push
// topic. Answers with the endpoint ARN, which the app writes down and hands
// back on the next launch.
//
// environment is what the build's own provisioning profile says - "production"
// or "development". Swift reads it; this side only trusts it.
//
// Called on every launch and safe to call on every launch: a token can change
// between two of them, and an endpoint can be switched off between two of them
// without anybody being told.
func (m *Mailbox) RegisterForPush(token, environment, storedEndpoint string) (string, error) {
	app := core.PlatformApp(m.setup.PushApps, core.PushEnvironment(environment))
	if app == "" {
		// Not an error worth stopping for. A mailbox set up before push
		// existed carries no ARNs, and a build whose environment has none
		// should say so rather than register against the other one.
		return "", errors.New("push_not_configured")
	}
	if m.setup.PushTopic == "" {
		return "", errors.New("push_not_configured")
	}

	p := awsx.NewPush(m.cfg, "")
	endpoint, err := p.Register(ctx(), app, storedEndpoint, token)
	if err != nil {
		return "", err
	}
	// Subscribing again costs one call and answers with the subscription that
	// is already there. Cheaper than remembering whether it happened, and it
	// repairs a subscription somebody removed by hand.
	if _, err := p.Subscribe(ctx(), m.setup.PushTopic, endpoint); err != nil {
		// The endpoint exists and is worth keeping even when the subscription
		// failed: the next launch will try again, and re-registering would
		// only make a second endpoint.
		return endpoint, err
	}
	return endpoint, nil
}

// CanPush says whether this mailbox was set up for push at all - both an
// application for this build's environment and a topic.
func (m *Mailbox) CanPush(environment string) bool {
	return m.setup.PushTopic != "" &&
		core.PlatformApp(m.setup.PushApps, core.PushEnvironment(environment)) != ""
}
