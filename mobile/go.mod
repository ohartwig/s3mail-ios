// Die Bruecke zwischen dem Go-Kern und Swift.
//
// Eigenes Modul, und das ist der Punkt: gomobile verlangt
// golang.org/x/mobile als Abhaengigkeit, und s3mail nimmt laut CLAUDE.md nur
// Standardbibliothek plus AWS-SDK und go-message. Die Abhaengigkeit gehoert
// also hierher und nicht dorthin - moeglich erst, seit der Kern einen
// aufloesbaren Modulpfad hat.
module github.com/ohartwig/s3mail-ios/mobile

go 1.27.0

// Der Kern kommt als Version, wie jede andere Abhaengigkeit.
//
// Sein Modulpfad ist github.com/ohartwig/s3mail, seine go.mod liegt seit
// 2026-09-14 im Wurzelverzeichnis, und vX.Y.Z ist die Version. Bis dahin
// zeigte ein replace auf ein Schwester-Checkout; damit baute dieses Repo nur
// in genau einer Verzeichnisstruktur, und jedes `go mod tidy` ausserhalb -
// etwa das einer Abhaengigkeitsaktualisierung - scheiterte.
//
// Solange der oeffentliche Spiegel auf GitHub nicht steht, holt Go den Kern
// von GitLab: das replace unten zeigt auf denselben Stand unter dem
// GitLab-Pfad (das Fork-Muster - die go.mod dort traegt den GitHub-Namen).
// Dafuer GOPRIVATE=git.ole-hartwig.eu und eine Anmeldung in ~/.netrc, lokal
// wie in der Pipeline (.gitlab-ci.yml sagt wie). Mit dem Spiegel faellt das
// replace weg, und mit ihm GOPRIVATE und die Anmeldung.
replace github.com/ohartwig/s3mail => git.ole-hartwig.eu/development/s3mail/s3mail v1.6.0

require (
	github.com/aws/aws-sdk-go-v2 v1.47.0
	github.com/ohartwig/s3mail v1.6.0
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
