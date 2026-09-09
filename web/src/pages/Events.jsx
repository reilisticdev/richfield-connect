import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

function formatLabel(value) {
  return value.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function Events() {
  const [events, setEvents] = useState([]);
  const [loadingEvents, setLoadingEvents] = useState(true);
  const [error, setError] = useState(null);

  const [title, setTitle] = useState("");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [location, setLocation] = useState("");

  const [editingEventId, setEditingEventId] = useState(null);

  const fetchEvents = async () => {
    setLoadingEvents(true);

    const { data, error } = await supabase
      .from("events")
      .select("*")
      .order("event_date", { ascending: true });

    if (error) {
      console.error("Error fetching events:", error);
      setError("Could not load events.");
      setEvents([]);
    } else {
      setEvents(data || []);
    }

    setLoadingEvents(false);
  };

  useEffect(() => {
    fetchEvents();
  }, []);

  const startEditing = (event) => {
    const when = new Date(event.event_date);

    const dateValue = `${when.getFullYear()}-${String(
      when.getMonth() + 1
    ).padStart(2, "0")}-${String(when.getDate()).padStart(2, "0")}`;

    const timeValue = `${String(when.getHours()).padStart(2, "0")}:${String(
      when.getMinutes()
    ).padStart(2, "0")}`;

    setEditingEventId(event.id);
    setTitle(event.title);
    setDate(dateValue);
    setTime(timeValue);
    setLocation(event.location || "");
  };

  const updateEvent = async (e) => {
     e.preventDefault();

     if (!editingEventId || !title || !date || !time || !location) {
       return;
      }

     const event_date = new Date(`${date}T${time}`).toISOString();

    const { error } = await supabase
      .from("events")
      .update({
         title,
         event_date,
         location,
       })
      .eq("id", editingEventId);

    if (error) {
       console.error("Error updating event:", error);
       setError("Could not update event.");
       return;
     }

     setEditingEventId(null);
     setTitle("");
     setDate("");
     setTime("");
     setLocation("");

     fetchEvents();
  };

  const createEvent = async (e) => {
    e.preventDefault();

    if (!title || !date || !time || !location) {
      return;
    }

    const {
      data: { user },
    } = await supabase.auth.getUser();
    const event_date = new Date(`${date}T${time}`).toISOString();

    const { error } = await supabase.from("events").insert({
      title,
      event_date,
      location,
      status: "draft",
      created_by: user.id,
    });

    if (error) {
      console.error("Error creating event:", error);
      setError("Could not create event.");
      return;
    }

    setTitle("");
    setDate("");
    setTime("");
    setLocation("");
    fetchEvents();
  };

  const publishEvent = async (id) => {
    const { error } = await supabase
      .from("events")
      .update({ status: "published" })
      .eq("id", id);

    if (error) {
      console.error("Error publishing event:", error);
      setError("Could not publish event.");
      return;
    }

    setEvents((current) =>
      current.map((event) =>
        event.id === id ? { ...event, status: "published" } : event
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

      {error && <p className="form-error">{error}</p>}

      {/* Create Event */}
      <section className="admin-section">
        <div className="section-header">
          <div>
            <h2>{editingEventId ? "Edit Event" : "Create Event"}</h2>
            <p>
              {editingEventId
                 ? "Update the details of this official Richfield event."
                 : "Add an official event to the Richfield Connect platform."}
            </p>
          </div>
        </div>

        <form
           className="event-form"
           onSubmit={editingEventId ? updateEvent : createEvent}
        >
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
            {editingEventId ? "Save Changes" : "Create Event"}
          </button>

          {editingEventId && (
            <button
            type="button"
             className="cancel-button"
             onClick={() => {
               setEditingEventId(null);
               setTitle("");
               setDate("");
               setTime("");
               setLocation("");
             }}
           >
             Cancel Edit
           </button>
         )}
         
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

          {loadingEvents ? (
            <div className="table-row">
              <div>Loading...</div>
            </div>
          ) : events.length === 0 ? (
            <div className="table-row">
              <div>
                <strong>No events yet</strong>
                <small>Create the first event using the form above.</small>
              </div>
            </div>
          ) : (
            events.map((event) => {
              const when = new Date(event.event_date);
              const dateLabel = when.toLocaleDateString("en-ZA", {
                day: "numeric",
                month: "long",
                year: "numeric",
              });
              const timeLabel = when.toLocaleTimeString("en-ZA", {
                hour: "2-digit",
                minute: "2-digit",
              });

              return (
                <div className="table-row" key={event.id}>
                  <div>
                    <strong>{event.title}</strong>

                    <small>
                      Official Richfield event
                    </small>
                  </div>

                  <div>
                    <strong>{dateLabel}</strong>
                    <small>{timeLabel}</small>
                  </div>

                  <div>{event.location}</div>

                  <div className="action-buttons">
                   <span
                       className={`status-badge ${event.status}`}
                   >
                       {formatLabel(event.status)}
                   </span>

                    <button
                       className="approve-button"
                       onClick={() => startEditing(event)}
                    >
                      Edit
                    </button>

                    {event.status === "draft" && (
                       <button
                        className="approve-button"
                         onClick={() => publishEvent(event.id)}
                       >
                         Publish
                       </button>
                    )}
                 </div>
                </div>
              );
            })
          )}
        </div>
      </section>
    </div>
  );
}

export default Events;
