importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyC_xeD9iE3tm9nxoA6R4nWmIb2ANucrlHI",
  authDomain: "uppibrazil.firebaseapp.com",
  projectId: "uppibrazil",
  storageBucket: "uppibrazil.firebasestorage.app",
  messagingSenderId: "408478040204",
  appId: "1:408478040204:web:a7f9910156128041257ba9"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification ? payload.notification.title : 'Mensagem Recebida';
  const notificationOptions = {
    body: payload.notification ? payload.notification.body : '',
    icon: '/favicon.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
