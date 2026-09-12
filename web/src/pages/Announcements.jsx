import { useState } from "react";
import { supabase } from "../lib/supabase";

const audienceToRole = {
  Everyone: null,
  Students: "student",
  Alumni: "alumni",
  "Business Users": "business",
};

function Announcements() {
  const [audience, setAudience] = useState("Everyone");
  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [successMessage, setSuccessMessage] = useState(null);

  const sendAnnouncement = async (e) => {
    e.preventDefault();

    const cleanTitle = title.trim();
    const cleanMessage = message.trim();

    setError(null);
    setSuccessMessage(null);

    // This used to return silently, so a blank form looked like a broken
    // button.
    if (!cleanTitle || !cleanMessage) {
      setError("Add a title and a message before sending.");
      return;
    }

    setSending(true);

    const { data, error } = await supabase.rpc("broadcast_announcement", {
      announcement_title: cleanTitle,
      announcement_message: cleanMessage,
      target_role: audienceToRole[audience],
    });

    if (error) {
      console.error("Error sending announcement:", error);
      // The RPC raises readable reasons (not an administrator, blank
      // message). A generic message is what hid migration 023's type bug.
      setError(error.message || "Could not send announcement.");
      setSending(false);
      return;
    }

    setSuccessMessage(`Sent to ${data} user${data === 1 ? "" : "s"}.`);
    setTitle("");
    setMessage("");
    setSending(false);
  };

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Announcements</h1>
          <p>
            Broadcast important announcements to users across the platform.
          </p>
        </div>
      </div>

      {error && <p className="form-error">{error}</p>}
      {successMessage && <p className="form-success">{successMessage}</p>}

      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Create Announcement</h2>
            <p>
              Send an announcement to everyone or a specific user group.
            </p>
          </div>
        </div>

        <form className="announcement-form" onSubmit={sendAnnouncement}>
          <div className="form-group">
            <label htmlFor="announcement-title">
              Announcement Title
            </label>

            <input
              type="text"
              id="announcement-title"
              placeholder="Enter announcement title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
          </div>

          <div className="form-group">
            <label htmlFor="announcement-audience">
              Audience
            </label>

            <select
              id="announcement-audience"
              value={audience}
              onChange={(e) => setAudience(e.target.value)}
            >
              <option value="Everyone">Everyone</option>
              <option value="Students">Students</option>
              <option value="Alumni">Alumni</option>
              <option value="Business Users">
                Business Users
              </option>
            </select>
          </div>

          <div className="form-group">
            <label htmlFor="announcement-message">
              Message
            </label>

            <textarea
              id="announcement-message"
              placeholder="Write your announcement..."
              rows="6"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
            />
          </div>

          <button type="submit" className="login-button" disabled={sending}>
            {sending ? "Sending..." : "Send Announcement"}
          </button>
        </form>
      </section>
    </div>
  );
}

export default Announcements;
