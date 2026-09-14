class PageNav < HyperComponent
  param :active
  param :tracker_name, default: nil
  param :tracker_color, default: "#2563eb"

  render do
    DIV(style: {
          display: "flex", alignItems: "center", gap: "0.75rem",
          flexWrap: "wrap", marginBottom: "1rem"
        }) do
      tab("Track me", "/me", active == :me)
      tab("Everyone", "/everyone", active == :everyone)

      DIV(style: { flex: "1 1 auto" })

      if tracker_name
        DIV(style: { display: "flex", alignItems: "center", gap: "0.5rem" }) do
          SPAN(style: {
                 width: "14px", height: "14px", borderRadius: "50%",
                 background: tracker_color, display: "inline-block",
                 border: "2px solid #fff", boxShadow: "0 1px 4px rgba(0,0,0,.35)"
               })
          SPAN(style: { fontSize: "1rem", color: "#374151" }) { "You are #{tracker_name}" }
        end
      end
    end
  end

  def tab(label, href, current)
    A(
      href: href,
      style: {
        padding: "0.5rem 0.9rem",
        borderRadius: "999px",
        fontSize: "1rem",
        textDecoration: "none",
        fontWeight: current ? "600" : "400",
        background: current ? "#111827" : "#e5e7eb",
        color: current ? "#ffffff" : "#374151"
      }
    ) { label }
  end
end
