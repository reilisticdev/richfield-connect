import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

// Same fixed list as the mobile app's campus dropdown (main.dart _campuses) -
// keeps spelling consistent across both clients for the same free-text
// campus concept used throughout (education, verification claims, events).
const CAMPUSES = [
  "Bryanston",
  "Newtown Junction",
  "Centurion",
  "Pretoria",
  "Umhlanga",
  "Musgrave",
  "Cape Town",
  "Polokwane",
];

// Events created before the list was corrected hold locations that are not
// options any more ("Braamfontein Campus", "Durban, Umhlanga"). Without this
// the edit form would render a blank select and silently rewrite the location
// on the next save, so the stored value is offered alongside the real ones.
const campusOptions = (current) => {
  const value = (current ?? "").trim();
  return value && !CAMPUSES.includes(value) ? [...CAMPUSES, value] : CAMPUSES;
};

// Per Miss Amishka's guidance: an admin creating an event or announcement
// should never be able to pick a date before this year - catches the
// classic "typed 2025 by habit" mistake.
const MIN_EVENT_DATE = "2026-01-01";

function formatLabel(value) {
  return value.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function Events() {
  const [events, setEvents] = useState([]);
  const [loadingEvents, setLoadingEvents] = useState(true);
  const [error, setError] = useState(null);
  const [showArchived, setShowArchived] = useState(false);

  const [title, setTitle] = useState("");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [location, setLocation] = useState("");

  const [editingEventId, setEditingEventId] = useState(null);

  // Delete asks for a second click on the row instead of window.confirm():
  // embedded browsers such as VS Code's can block native dialogs, and a
  // blocked confirm() returns false, so Delete would silently do nothing.
  const [confirmingDeleteId, setConfirmingDeleteId] = useState(null);
  const [deletingId, setDeletingId] = useState(null);

  const fetchEvents = useCallback(async () => {
    setLoadingEvents(true);

    // "Show archived" reveals everything (active + archived) rather than
    // switching to an archived-only view, so an admin can see and restore
    // an archived event in the same list it would normally sit in.
    let query = supabase
      .from("events")
      .select("*")
      .order("event_date", { ascending: true });
    if (!showArchived) {
      query = query.is("archived_at", null);
    }
    const { data, error } = await query;

    if (error) {
      console.error("Error fetching events:", error);
      setError("Could not load events.");
      setEvents([]);
    } else {
      setEvents(data || []);
    }

    setLoadingEvents(false);
  }, [showArchived]);

  useEffect(() => {
    fetchEvents();
  }, [fetchEvents]);

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

     if (date < MIN_EVENT_DATE) {
       setError("Event date can't be before 2026.");
       return;
     }

     const event_date = new Date(`${date}T${time}`).toISOString();

    // RLS turns a disallowed update into zero rows rather than an error, so
    // ask for the updated row back and treat an empty result as a failure.
    const { data, error } = await supabase
      .from("events")
      .update({
         title,
         event_date,
         location,
       })
      .eq("id", editingEventId)
      .select("id");

    if (error || !data?.length) {
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

    if (date < MIN_EVENT_DATE) {
      setError("Event date can't be before 2026.");
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

  const deleteEvent = async (event) => {
    setError(null);
    setDeletingId(event.id);

    // RLS turns a disallowed delete into zero rows rather than an error, so
    // ask for the deleted row back and treat an empty result as a failure.
    const { data, error } = await supabase
      .from("events")
      .delete()
      .eq("id", event.id)
      .select("id");

    setDeletingId(null);
    setConfirmingDeleteId(null);

    if (error || !data?.length) {
      console.error("Error deleting event:", error);
      setError("Could not delete event.");
      return;
    }

    if (editingEventId === event.id) {
      setEditingEventId(null);
      setTitle("");
      setDate("");
      setTime("");
      setLocation("");
    }

    setEvents((current) => current.filter((item) => item.id !== event.id));
  };

  const restoreEvent = async (id) => {
    setError(null);

    const { error } = await supabase
      .from("events")
      .update({ archived_at: null })
      .eq("id", id);

    if (error) {
      console.error("Error restoring event:", error);
      setError("Could not restore event.");
      return;
    }

    // Restore is only ever rendered on an archived row, which is only ever
    // visible while showArchived is on - so this always just flips the row
    // back to active in place rather than needing to hide it.
    setEvents((current) =>
      current.map((event) =>
        event.id === id ? { ...event, archived_at: null } : event
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
                min={MIN_EVENT_DATE}
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
              <select
                id="event-location"
                value={location}
                onChange={(e) => setLocation(e.target.value)}
              >
                <option value="">Select a campus</option>
                {campusOptions(location).map((campus) => (
                  <option key={campus} value={campus}>
                    {campus}
                  </option>
                ))}
              </select>
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

          <div className="section-header-actions">
            <label className="show-archived-toggle">
              <input
                type="checkbox"
                checked={showArchived}
                onChange={(e) => setShowArchived(e.target.checked)}
              />
              Show archived
            </label>

            <span className="count-badge">
              {events.length} Events
            </span>
          </div>
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

                    {event.archived_at && (
                      <span className="status-badge archived">Archived</span>
                    )}

                    {event.archived_at ? (
                      <button
                        className="approve-button"
                        onClick={() => restoreEvent(event.id)}
                      >
                        Restore
                      </button>
                    ) : (
                      <>
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
                      </>
                    )}

                    {confirmingDeleteId === event.id ? (
                      <>
                        <button
                          className="reject-button"
                          disabled={deletingId === event.id}
                          onClick={() => deleteEvent(event)}
                        >
                          {deletingId === event.id ? "Deleting..." : "Confirm delete"}
                        </button>
                        <button
                          className="cancel-button"
                          disabled={deletingId === event.id}
                          onClick={() => setConfirmingDeleteId(null)}
                        >
                          Cancel
                        </button>
                      </>
                    ) : (
                      <button
                        className="reject-button"
                        onClick={() => setConfirmingDeleteId(event.id)}
                      >
                        Delete
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
