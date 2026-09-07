import { useEffect, useState } from "react";
import { Navigate } from "react-router-dom";
import { supabase } from "../lib/supabase";

function RequireAdmin({ children }) {
  const [checked, setChecked] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);

  useEffect(() => {
    const checkAdmin = async () => {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) {
        setChecked(true);
        return;
      }

      const { data, error } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", session.user.id)
        .single();

      if (!error && data?.role === "administrator") {
        setIsAdmin(true);
      }

      setChecked(true);
    };

    checkAdmin();
  }, []);

  if (!checked) {
    return null;
  }

  return isAdmin ? children : <Navigate to="/login" replace />;
}

export default RequireAdmin;
