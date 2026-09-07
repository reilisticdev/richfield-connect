import { useState } from "react";

function Events() {
  const [events, setEvents] = useState([
    {
      id: 1,
      title: "Richfield Tech Club Meetup",
      date: "12 September 2026",
      time: "10:00 AM",
      location: "Umhlanga Campus",
      status: "Published",
    },
    {
      id: 2,
      title: "Career Development Workshop",
      date: "18 September 2026",
      time: "1:00 PM",
      location: "Main Lecture Hall",
      status: "Draft",
    },
  ]);

  const [title, setTitle] = useState("");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [location, setLocation] = useState("");

  const createEvent = (e) => {
    e.preventDefault();

    if (!title || !date || !time || !location) {
      return;
    }

    const newEvent = {
      id: Date.now(),
      title,
      date,
      time,
      location,
      status: "Draft",
    };

    setEvents((current) => [...current, newEvent]);

    setTitle("");
    setDate("");
    setTime("");
    setLocation("");
  };

  const publishEvent = (id) => {
    setEvents((current) =>
      current.map((event) =>
        event.id === id
          ? { ...event, status: "Published" }
          : event
      )
    );
  };

  return (
    <div className="admin-page">
      <div className="page-header">
        <div>
          <h1>Event Management</h1>
          <p>
            Create, manage, and publish official Richfield institutional
            events.
          </p>
        </div>
      </div>

      {/* Create Event */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Create Event</h2>
            <p>
              Add an official event to the Richfield Connect platform.
            </p>
          </div>
        </div>

        <form className="event-form" onSubmit={createEvent}>
          <div className="form-group">
            <label htmlFor="event-title"> Event Title</label>
            <input
              type="text"
              id="event-title"
              placeholder="Enter event title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
          </div>

          <div className="event-form-row">
            <div className="form-group">
              <label htmlFor="event-date">Date</label>
              <input
                type="date"
                id="event-date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="event-time">Time</label>
              <input
                type="time"
                id="event-time"
                value={time}
                onChange={(e) => setTime(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="event-location">Location</label>
              <input
                type="text"
                id="event-location"
                placeholder="Enter location"
                value={location}
                onChange={(e) => setLocation(e.target.value)}
              />
            </div>
          </div>

          <button type="submit" className="login-button event-create-button">
            Create Event
          </button>
        </form>
      </section>

      {/* Event List */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>Official Events</h2>
            <p>
              Manage events that appear on the Richfield Connect platform.
            </p>
          </div>

          <span className="count-badge">
            {events.length} Events
          </span>
        </div>

        <div className="moderation-table">
          <div className="table-header">
            <span>Event</span>
            <span>Date & Time</span>
            <span>Location</span>
            <span>Actions</span>
          </div>

          {events.map((event) => (
            <div className="table-row" key={event.id}>
              <div>
                <strong>{event.title}</strong>

                <small>
                  Official Richfield event
                </small>
              </div>

              <div>
                <strong>{event.date}</strong>
                <small>{event.time}</small>
              </div>

              <div>{event.location}</div>

              <div className="action-buttons">
                <span
                  className={`status-badge ${event.status.toLowerCase()}`}
                >
                  {event.status}
                </span>

                {event.status === "Draft" && (
                  <button
                    className="approve-button"
                    onClick={() => publishEvent(event.id)}
                  >
                    Publish
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

export default Events;