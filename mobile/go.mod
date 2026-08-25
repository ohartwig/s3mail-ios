// Die Bruecke zwischen dem Go-Kern und Swift.
//
// Eigenes Modul, und das ist der Punkt: gomobile verlangt
// golang.org/x/mobile als Abhaengigkeit, und s3mail nimmt laut CLAUDE.md nur
// Standardbibliothek plus AWS-SDK und go-message. Die Abhaengigkeit gehoert
// also hierher und nicht dorthin - moeglich erst, seit der Kern einen
// aufloesbaren Modulpfad hat.
module git.ole-hartwig.eu/development/s3mail/ios/mobile

go 1.26.0

replace git.ole-hartwig.eu/development/s3mail/s3mail => /Volumes/Samsung_X5/Projects/S3mail/go

require (
	git.ole-hartwig.eu/development/s3mail/s3mail v0.0.0
	golang.org/x/mobile v0.0.0-20260821190718-4776eadac327
)

require (
	github.com/emersion/go-message v0.18.2 // indirect
	golang.org/x/mod v0.39.0 // indirect
	golang.org/x/sync v0.22.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	golang.org/x/tools v0.49.0 // indirect
)
