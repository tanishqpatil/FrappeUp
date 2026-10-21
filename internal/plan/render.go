package plan

import (
	"fmt"
	"strings"
)

func RenderText(p Plan) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Profile: %s\nProject: %s\nSite: %s\n", p.Profile, p.ProjectName, p.SiteName)
	fmt.Fprintf(&b, "Frappe: %s @ %s (%s)\n", p.Frappe.Repository, p.Frappe.Ref, p.Frappe.RefKind)
	fmt.Fprintf(&b, "Frappe Docker: %s @ %s (%s)\n", p.FrappeDocker.Repository, p.FrappeDocker.Ref, p.FrappeDocker.RefKind)
	if len(p.Apps) == 0 {
		b.WriteString("Apps: none\n")
	} else {
		b.WriteString("Apps (install order):\n")
		for _, app := range p.Apps {
			fmt.Fprintf(&b, "  - %s [%s] @ %s\n", app.ID, app.RefKind, app.Ref)
		}
	}
	if p.LockRequired {
		b.WriteString("Lock: required before a production install\n")
	}
	for _, warning := range p.Warnings {
		fmt.Fprintf(&b, "Warning: %s\n", warning)
	}
	return b.String()
}
