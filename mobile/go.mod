// Die Bruecke zwischen dem Go-Kern und Swift.
//
// Eigenes Modul, und das ist der Punkt: gomobile verlangt
// golang.org/x/mobile als Abhaengigkeit, und s3mail nimmt laut CLAUDE.md nur
// Standardbibliothek plus AWS-SDK und go-message. Die Abhaengigkeit gehoert
// also hierher und nicht dorthin - moeglich erst, seit der Kern einen
// aufloesbaren Modulpfad hat.
module git.ole-hartwig.eu/development/s3mail/ios/mobile

go 1.27.0

// Der Kern liegt als Schwesterverzeichnis, nicht als Version.
//
// Sein Modulpfad ist git.ole-hartwig.eu/development/s3mail/s3mail, die go.mod
// steht aber unter go/ - Go suchte sie im Wurzelverzeichnis des Repos und
// faende nichts. Ein `go get` auf den Tag geht also nicht, solange das so ist.
//
// Der Pfad ist relativ und nicht absolut: sonst baut dieses Repo nur auf dem
// einen Rechner, auf dem jemand es einmal eingerichtet hat. Erwartet wird ein
// Auscheck von development/s3mail/s3mail als Schwesterverzeichnis:
//
//     projekte/
//       s3mail/       <- der Kern
//       s3mail-ios/   <- dieses Repo
replace git.ole-hartwig.eu/development/s3mail/s3mail => ../../s3mail/go

require (
	git.ole-hartwig.eu/development/s3mail/s3mail v0.0.0
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
