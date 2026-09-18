// The bridge between the Go core and Swift.
//
// A module of its own, and that is the point: gomobile requires
// golang.org/x/mobile, and the core takes nothing beyond the standard
// library, the AWS SDK and go-message. The dependency belongs here, not
// there - possible only since the core has a resolvable module path.
module github.com/ohartwig/s3mail-ios/mobile

go 1.27.0

// The core is a versioned dependency like any other.
//
// Its module path is github.com/ohartwig/s3mail; its go.mod has lived at the
// repository root since 2026-09-14, so vX.Y.Z is the version. Before that a
// replace pointed at a sibling checkout, which made this repository build in
// exactly one directory layout and failed every `go mod tidy` outside it -
// the one a dependency update runs, for instance.
//
// Public since 2026-09-15, so it comes through the proxy and the checksum
// database like every other dependency; until then a replace pointed at the
// same revision under the GitLab path, with GOPRIVATE and a login.

require (
	github.com/aws/aws-sdk-go-v2 v1.47.0
	github.com/ohartwig/s3mail v1.6.2
	golang.org/x/mobile v0.0.0-20260908204917-8b95e45f8d3e
)

require (
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.7.18 // indirect
	github.com/aws/aws-sdk-go-v2/config v1.32.38 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.19.37 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.18.38 // indirect
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.4.39 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.7.39 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.4.39 // indirect
	github.com/aws/aws-sdk-go-v2/service/iam v1.59.2 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.13.17 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.9.31 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.13.38 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.19.39 // indirect
	github.com/aws/aws-sdk-go-v2/service/kms v1.55.7 // indirect
	github.com/aws/aws-sdk-go-v2/service/s3 v1.107.3 // indirect
	github.com/aws/aws-sdk-go-v2/service/ses v1.37.7 // indirect
	github.com/aws/aws-sdk-go-v2/service/sesv2 v1.67.0 // indirect
	github.com/aws/aws-sdk-go-v2/service/signin v1.5.7 // indirect
	github.com/aws/aws-sdk-go-v2/service/sns v1.42.8 // indirect
	github.com/aws/aws-sdk-go-v2/service/sqs v1.46.7 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.33.7 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.38.7 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.45.7 // indirect
	github.com/aws/smithy-go v1.28.1 // indirect
	github.com/emersion/go-message v0.18.2 // indirect
	golang.org/x/mod v0.41.0 // indirect
	golang.org/x/sync v0.23.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	golang.org/x/tools v0.50.0 // indirect
)
