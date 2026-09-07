import { useState } from "react";

function Announcements() {
  const [audience, setAudience] = useState("Everyone");
  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");

  const sendAnnouncement = (e) => {
    e.preventDefault();

    if (!title || !message) {
      return;
    }

    alert(`Announcement sent to ${audience}.`);

    setTitle("");
    setMessage("");
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

          <button type="submit" className="login-button">
            Send Announcement
          </button>
        </form>
      </section>
    </div>
  );
}

export default Announcements;