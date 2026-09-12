import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import "./App.css";

import Sidebar from "./components/Sidebar";
import RequireAdmin from "./components/RequireAdmin";

import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Users from "./pages/Users";
import Moderation from "./pages/Moderation";
import Opportunities from "./pages/Opportunities";
import Events from "./pages/Events";
import Announcements from "./pages/Announcements";
import Analytics from "./pages/Analytics";
import AuditLog from "./pages/AuditLog";

function AdminLayout({ children }) {
  return (
    <div className="admin-layout">
      <Sidebar />
      <main className="main-content">
        {children}
      </main>
    </div>
  );
}

function ProtectedAdminPage({ children }) {
  return (
    <RequireAdmin>
      <AdminLayout>{children}</AdminLayout>
    </RequireAdmin>
  );
}

function App() {
  return (
    <BrowserRouter>
      <Routes>

        {/* Public login page */}
        <Route path="/login" element={<Login />} />

        {/* Redirect the home page to login */}
        <Route
          path="/"
          element={<Navigate to="/login" replace />}
        />

        {/* Protected administrator pages */}
        <Route
          path="/dashboard"
          element={
            <ProtectedAdminPage>
              <Dashboard />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/users"
          element={
            <ProtectedAdminPage>
              <Users />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/moderation"
          element={
            <ProtectedAdminPage>
              <Moderation />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/opportunities"
          element={
            <ProtectedAdminPage>
              <Opportunities />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/events"
          element={
            <ProtectedAdminPage>
              <Events />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/announcements"
          element={
            <ProtectedAdminPage>
              <Announcements />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/analytics"
          element={
            <ProtectedAdminPage>
              <Analytics />
            </ProtectedAdminPage>
          }
        />

        <Route
          path="/audit-log"
          element={
            <ProtectedAdminPage>
              <AuditLog />
            </ProtectedAdminPage>
          }
        />

        {/* Unknown routes return to login */}
        <Route
          path="*"
          element={<Navigate to="/login" replace />}
        />

      </Routes>
    </BrowserRouter>
  );
}

export default App;
