/* Adaptador mínimo para manter o frontend original sem dependências externas. */
window.supabase = {
  createClient(baseUrl) {
    return {
      async rpc(name, params = {}) {
        try {
          const response = await fetch(`${baseUrl}/api/rpc/${encodeURIComponent(name)}`, {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify(params),
          });
          const payload = await response.json();
          if (!response.ok) return {data: null, error: {message: payload.error || "Erro inesperado"}};
          return {data: payload.data, error: null};
        } catch (error) {
          return {data: null, error: {message: error.message}};
        }
      },
    };
  },
};
