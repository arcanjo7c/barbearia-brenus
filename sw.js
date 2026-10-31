// Service worker mínimo: deixa o site instalável como aplicativo. Não guarda nada em cache, então os horários são sempre os atuais.
self.addEventListener("install",function(){self.skipWaiting()});
self.addEventListener("activate",function(e){e.waitUntil(self.clients.claim())});
self.addEventListener("fetch",function(){});
