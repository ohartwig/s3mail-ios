// Die Bruecke zwischen dem Go-Kern und Swift.
//
// Eigenes Modul, und das ist der Punkt: gomobile verlangt
// golang.org/x/mobile als Abhaengigkeit, und s3mail nimmt laut CLAUDE.md nur
// Standardbibliothek plus AWS-SDK und go-message. Die Abhaengigkeit gehoert
// also hierher und nicht dorthin - moeglich erst, seit der Kern einen
// aufloesbaren Modulpfad hat.
module git.ole-hartwig.eu/development/s3mail/ios/mobile

go 1.27.0

// Der Kern kommt als Version, wie jede andere Abhaengigkeit.
//
// Sein Modulpfad ist git.ole-hartwig.eu/development/s3mail/s3mail/go - mit
// dem /go, weil seine go.mod unter go/ steht und Go ein Untermodul nach seinem
// Verzeichnis benennt. Versioniert ist es unter den Tags go/vX.Y.Z, die der
// Kern neben vX.Y.Z setzt. Bis 2026-09-14 zeigte ein replace auf ein
// Schwester-Checkout; damit baute dieses Repo nur in genau einer
// Verzeichnisstruktur, und jedes `go mod tidy` ausserhalb - etwa das einer
// Abhaengigkeitsaktualisierung - scheiterte.
//
// Der Kern ist nicht oeffentlich: GOPRIVATE=git.ole-hartwig.eu und eine
// Anmeldung in ~/.netrc, lokal wie in der Pipeline (.gitlab-ci.yml sagt wie).
require (
	git.ole-hartwig.eu/development/s3mail/s3mail/go v1.5.0
	github.com/aws/aws-sdk-go-v2 v1.43.8
	golang.org/x/mobile v0.0.0-20260821190718-4776eadac327
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
	github.com/aws/smithy-go v1.27.10 // indirect
	github.com/emersion/go-message v0.18.2 // indirect
	golang.org/x/mod v0.39.0 // indirect
	golang.org/x/sync v0.22.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	golang.org/x/tools v0.49.0 // indirect
)
