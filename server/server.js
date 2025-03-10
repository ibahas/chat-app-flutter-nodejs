const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const sqlite3 = require('sqlite3').verbose();
const { open } = require('sqlite');
const path = require('path');
const multer = require('multer'); // Import multer
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

// JWT Secret (use environment variables in production)
const JWT_SECRET = 'auth_token';

// Database setup
let db;

// Multer setup for file uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = 'uploads/';
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    cb(null, dir); // Specify the upload directory
  },
  filename: (req, file, cb) => {
    cb(null, Date.now() + '-' + file.originalname); // Define the filename
  },
});

const upload = multer({ storage: storage });

// Endpoint for file uploads
app.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).send({ message: 'No file uploaded' });
  }

  // Construct the file URL
  const fileUrl = `${req.protocol}://${req.get('host')}/${req.file.path}`;

  res.status(200).send({ message: 'File uploaded successfully', url: fileUrl });
});

async function initializeDatabase() {
  // Open database connection
  db = await open({
    filename: path.join(__dirname, 'chat_app.db'),
    driver: sqlite3.Database
  });

  // Create tables if they don't exist
  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user',
      is_blocked INTEGER DEFAULT 0,
      ip_address TEXT DEFAULT '',
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS conversation_participants (
      conversation_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      PRIMARY KEY (conversation_id, user_id),
      FOREIGN KEY (conversation_id) REFERENCES conversations(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      admin_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (admin_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS group_members (
      group_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      PRIMARY KEY (group_id, user_id),
      FOREIGN KEY (group_id) REFERENCES groups(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      content TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      type TEXT NOT NULL,
      FOREIGN KEY (group_id) REFERENCES groups(id),
      FOREIGN KEY (sender_id) REFERENCES users(id)
    );
  `);

  // Create default users if they don't exist
  await createDefaultUsers();
}

async function createDefaultUsers() {
  const defaultUsers = [
    {
      id: '1',
      email: 'user@user.com',
      name: 'User',
      password: await bcrypt.hash('123456', 10),
      role: 'user',
      is_blocked: 0,
      created_at: new Date().toISOString()
    },
    {
      id: '2',
      email: 'admin@admin.com',
      name: 'Admin',
      password: await bcrypt.hash('123456', 10),
      role: 'admin',
      is_blocked: 0,
      created_at: new Date().toISOString()
    }
  ];

  for (const user of defaultUsers) {
    // Check if user exists
    const existingUser = await db.get('SELECT * FROM users WHERE email = ?', user.email);
    if (!existingUser) {
      await db.run(
        'INSERT INTO users (id, email, name, password, role, is_blocked, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [user.id, user.email, user.name, user.password, user.role, user.is_blocked, user.created_at]
      );
      console.log(`Default user created: ${user.email}`);
    }
  }
}

// Socket.io middleware for authentication
io.use(async (socket, next) => {
  const token = socket.handshake.auth.token;
  if (!token) {
    console.log('Not authenticated');
    return next(); // Allow connection but user is not authenticated
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    socket.userId = decoded.userId;

    // Get user from database
    const user = await db.get('SELECT * FROM users WHERE id = ?', decoded.userId);
    if (user) {
      if (user.is_blocked === 1) {
        console.log('User is blocked');
        return next(new Error('User is blocked'));
      }
      socket.user = user;
    }

    next();
  } catch (err) {
    next(new Error('Authentication error'));
  }
});


io.on('connection', (socket) => {
  console.log('New client connected:', socket.id);

  // ===== AUTHENTICATION EVENTS =====

  // Register new user
  socket.on('register', async (data, callback) => {
    console.log(`register`);

    try {
      const { email, password, name, role = 'user' } = data;

      // Check if email already exists
      const existingUser = await db.get('SELECT * FROM users WHERE email = ?', email);
      if (existingUser) {
        console.log('Email already in use');
        return callback({ success: false, message: 'Email already in use' });
      }

      // Hash password
      const hashedPassword = await bcrypt.hash(password, 10);

      // Create new user
      const userId = Date.now().toString();
      const createdAt = new Date().toISOString();

      await db.run(
        'INSERT INTO users (id, email, name, password, role, is_blocked, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [userId, email, name, hashedPassword, role, 0, createdAt]
      );

      // Get the new user
      const newUser = await db.get('SELECT * FROM users WHERE id = ?', userId);

      // Generate token
      const token = jwt.sign({ userId }, JWT_SECRET, { expiresIn: '7d' });

      // Associate user with socket
      socket.userId = userId;
      socket.user = newUser;

      console.log('New user registered:', newUser.email);

      // Return success with user and token
      callback({
        success: true,
        token,
        user: {
          id: newUser.id,
          email: newUser.email,
          name: newUser.name,
          role: newUser.role,
          isBlocked: newUser.is_blocked === 1
        }
      });
    } catch (error) {
      console.log('Register error:', error);
      callback({ success: false, message: 'Registration failed' });
    }
  });

  // Login
  socket.on('login', async (data, callback) => {
    console.log(`login`);

    try {
      const { email, password } = data;

      // Find user by email
      const user = await db.get('SELECT * FROM users WHERE email = ?', email);
      if (!user) {
        console.log('Invalid credentials');
        return callback({ success: false, message: 'Invalid credentials' });
      }

      // Check if user is blocked
      if (user.is_blocked === 1) {
        console.log('Account is blocked');
        return callback({ success: false, message: 'Account is blocked' });
      }

      // Compare password
      const validPassword = await bcrypt.compare(password, user.password);
      if (!validPassword) {
        console.log('Invalid credentials');
        return callback({ success: false, message: 'Invalid credentials' });
      }
      //Check if ip_address is exits check it .
      if (user.ip_address) {
        //Get ip and check if it's == user.ip_address
        var currentIp = socket.handshake.address;
        if (user.ip_address !== currentIp) {
          console.log('Ip address');
          return callback({ success: false, message: 'Invalid credentials' });
        }
      }


      // Generate token
      const token = jwt.sign({ userId: user.id }, JWT_SECRET, { expiresIn: '7d' });

      // Associate user with socket
      socket.userId = user.id;
      socket.user = user;

      console.log('User logged in:', user.email);

      // Return success with user and token
      callback({
        success: true,
        token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          isBlocked: user.is_blocked === 1
        }
      });
    } catch (error) {
      console.log('Login error:', error);
      callback({ success: false, message: 'Login failed' });
    }
  });

  // Get user info
  socket.on('getUserInfo', async (data, callback) => {
    console.log(`getUserInfo`);
    if (!socket.userId) {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Not authenticated' });
    }

    try {
      const user = await db.get('SELECT * FROM users WHERE id = ?', socket.userId);
      if (!user) {
        return callback({ success: false, message: 'User not found' });
      }

      callback({
        success: true,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          isBlocked: user.is_blocked === 1
        }
      });
    } catch (error) {
      console.log('Get user info error:', error);
      callback({ success: false, message: 'Failed to get user info' });
    }
  });

  // Check admin status
  socket.on('checkAdminStatus', async (data, callback) => {
    console.log(`checkAdminStatus`);
    try {
      const { userId } = data;
      const user = await db.get('SELECT * FROM users WHERE id = ?', userId);

      if (!user) {
        return callback({ success: false, message: 'User not found' });
      }

      callback({
        success: true,
        isAdmin: user.role === 'admin'
      });
    } catch (error) {
      console.log('Check admin status error:', error);
      callback({ success: false, message: 'Failed to check admin status' });
    }
  });

  // Logout
  socket.on('logout', (_, callback) => {
    console.log(`logout`);
    socket.userId = null;
    socket.user = null;
    callback({ success: true });
  });

  // ===== ADMIN SERVICE HANDLERS =====

  // Get all users (admin only)
  socket.on('admin:getAllUsers', async (_, callback) => {
    console.log(`admin:getAllUsers`);
    //If role is user  return only users names.
    if (socket.user && socket.user.role !== 'admin') {
      try {
        const users = await db.all('SELECT id, name FROM users where role != admin');
        callback({
          success: true,
          data: users.map(user => ({
            id: user.id,
            name: user.name
          }))
        });
      } catch (error) {
        console.log('Get all users error:', error);
        callback({ success: false, message: 'Failed to get users' });
      }
    }
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      return callback({ success: false, message: 'Unauthorized' });
    }

    try {
      const users = await db.all('SELECT id, email, name, role, is_blocked, created_at FROM users');
      callback({
        success: true,
        data: users.map(user => ({
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          isBlocked: user.is_blocked === 1,
          createdAt: user.created_at
        }))
      });
    } catch (error) {
      console.log('Get all users error:', error);
      callback({ success: false, message: 'Failed to get users' });
    }
  });

  // Block user (admin only)
  socket.on('admin:blockUser', async (data, callback) => {
    console.log(`admin:blockUser`);
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      return callback({ success: false, message: 'Unauthorized' });
    }

    try {
      const { userId } = data;

      // Prevent blocking the admin himself
      if (userId === socket.userId) {
        return callback({ success: false, message: 'Cannot block yourself' });
      }

      await db.run('UPDATE users SET is_blocked = 1 WHERE id = ?', userId);

      // Find sockets for this user
      const userSockets = Array.from(io.sockets.sockets.values())
        .filter(s => s.userId === userId);

      // Disconnect the user sockets
      userSockets.forEach(userSocket => {
        userSocket.emit('forceLogout', { message: 'You have been blocked by the admin.' }); // Add message data
        userSocket.disconnect(true); // Disconnect the socket
      });

      callback({ success: true });
    } catch (error) {
      console.log('Block user error:', error);
      callback({ success: false, message: 'Failed to block user' });
    }
  });

  // Unblock user (admin only)
  socket.on('admin:unblockUser', async (data, callback) => {
    console.log(`admin:unblockUser`);
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      return callback({ success: false, message: 'Unauthorized' });
    }

    try {
      const { userId } = data;
      await db.run('UPDATE users SET is_blocked = 0 WHERE id = ?', userId);

      // Find sockets for this user
      const userSockets = Array.from(io.sockets.sockets.values())
        .filter(s => s.userId === userId);

      //Emit function to re-login
      userSockets.forEach(userSocket => {
        userSocket.emit('forceReLogin', { message: 'You have been unblocked by the admin, please re-login.' }); // Add message data
      });
      callback({ success: true });
    } catch (error) {
      console.log('Unblock user error:', error);
      callback({ success: false, message: 'Failed to unblock user' });
    }
  });

  // Get all groups (admin only)
  socket.on('admin:getAllGroups', async (_, callback) => {
    console.log(`admin:getAllGroups`);
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      return callback({ success: false, message: 'Unauthorized' });
    }

    try {
      const groups = await db.all('SELECT id, name, admin_id FROM groups');

      const result = [];
      for (const group of groups) {
        const members = await db.all(`
          SELECT user_id FROM group_members WHERE group_id = ?
        `, group.id);

        result.push({
          id: group.id,
          name: group.name,
          adminId: group.admin_id,
          members: members.map(m => m.user_id)
        });
      }

      callback({
        success: true,
        data: result
      });
    } catch (error) {
      console.log('Get all groups error:', error);
      callback({ success: false, message: 'Failed to get groups' });
    }
  });

  // Delete group (admin only)
  socket.on('admin:deleteGroup', async (data, callback) => {
    console.log(`admin:deleteGroup`);
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      return callback({ success: false, message: 'Unauthorized' });
    }

    try {
      const { groupId } = data;

      // Delete group members
      await db.run('DELETE FROM group_members WHERE group_id = ?', groupId);

      // Delete messages
      await db.run('DELETE FROM messages WHERE group_id = ?', groupId);

      // Delete the group
      await db.run('DELETE FROM groups WHERE id = ?', groupId);

      // Optionally, emit a group update event to notify clients
      io.emit('admin:groupUpdated', { id: groupId, deleted: true });


      // Notify users that the group was deleted and send the data
      const group = await db.get('SELECT id, name FROM groups WHERE id = ?', [groupId]);
      if (group) {
        // Get all members of the group
        const groupMembers = await db.all('SELECT user_id FROM group_members WHERE group_id = ?', groupId);

        // Iterate over each member and emit the event to their sockets
        for (const member of groupMembers) {
          const userSockets = Array.from(io.sockets.sockets.values()).filter(s => s.userId === member.user_id);
          const resultRemove = {
            id: group.id,
            name: group.name,
            message: "group was deleted."
          };

          userSockets.forEach(thesocket => thesocket?.emit('groupToWasRemoved', resultRemove));

          thesocket?.emit('groupToWasRemoved', (resultRemove));
        }
      }
      //Call for all to reload the peoples of group
      void await fetchUpdate(groupId, db);
      //Update list if success
      callback({ success: true });
    } catch (error) {
      console.log('Delete group error:', error);
      callback({ success: false, message: 'Failed to delete group' });
    }
  });

  // ===== GROUP MANAGEMENT =====

  // Get user groups
  socket.on('getUserGroups', async (data, callback) => {
    console.log(`getUserGroups`);
    if (!socket.userId) {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Not authenticated' });
    }

    try {
      const { userId } = data;

      // Fetch groups where the user is a member
      const groups = await db.all(`
        SELECT g.id, g.name, g.admin_id
        FROM groups g
        JOIN group_members gm ON g.id = gm.group_id
        WHERE gm.user_id = ?
      `, userId);

      // Get member ids for each group
      const result = [];
      for (const group of groups) {
        const members = await db.all(`
          SELECT user_id FROM group_members WHERE group_id = ?
        `, group.id);

        result.push({
          id: group.id,
          name: group.name,
          adminId: group.admin_id,
          members: members.map(m => m.user_id)
        });
      }

      callback({
        success: true,
        data: result
      });
    } catch (error) {
      console.log('Get user groups error:', error);
      callback({ success: false, message: 'Failed to get user groups' });
    }
  });

  // Send group message (Realtime)
  socket.on('sendGroupMessageRealTime', async (data, callback) => {
    console.log(`sendGroupMessageRealTime`);
    if (!socket.userId) {
      console.log('Not authenticated');
      return callback && callback({ success: false, message: 'Not authenticated' });
    }

    try {
      const { groupId, message } = data;
      const { senderId, content, type } = message;

      // Check if user is a member of the group (keep this check)
      const membership = await db.get('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?', [groupId, senderId]);

      if (!membership) {
        return callback && callback({ success: false, message: 'User is not a member of this group' });
      }

      const messageData = {
        // id: Date.now().toString(), // Generate a temporary ID (not saved)
        groupId: groupId,
        // senderId: senderId,
        content: content,
        timestamp: new Date().toISOString(),
        type: type
      };

      // Emit the message to all clients in the group
      io.to(`group:${groupId}`).emit(`groupMessages:${groupId}`, [messageData]);

      if (callback) {
        callback({ success: true });
      }
    } catch (error) {
      console.log('Send group message error:', error);
      if (callback) {
        callback({ success: false, message: 'Failed to send message' });
      }
    }
  });


  // Update group (admin only)
  socket.on('updateGroupName', async (data, callback) => {
    console.log(`updateGroupName`);

    // Check auth
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      return callback({ success: false, message: 'Unauthorized' });
    }

    try {
      const { groupId, name } = data;

      // Validate data
      if (!groupId || !name) {
        return callback({ success: false, message: 'Missing group ID or name' });
      }

      // Check if the user is an admin to modify.
      const groupF = await db.get('SELECT admin_id FROM groups WHERE id = ?', groupId);

      //Check if the user it's calling is an admin the group.
      if (groupF.admin_id !== socket.user.id) {
        console.log(`removeUserToGroup - User ID: ${socket.userId} is not an admin of group: ${groupId}`);
        return callback({ success: false, message: 'You are not authorized to add members from this group.' });
      }

      //Update the GroupName
      await db.run('UPDATE groups SET name = ? WHERE id = ?', [name, groupId]);

      //Send the update information
      //Update the GroupName
      const groupD = await db.get('SELECT id, name, admin_id FROM groups WHERE id = ?', [groupId]);
      //Convert to resualt.
      const members = await db.all(
        'SELECT user_id FROM group_members WHERE group_id = ?',
        [groupId]
      );
      let result = {
        id: groupD.id,
        name: groupD.name,
        adminId: groupD.admin_id,
        members: members.map(m => m.user_id)
      };

      io.emit('updateOfGroupName', result);

      callback({ success: true });
    } catch (error) {
      console.log('Error Update group:', error);
      callback({ success: false, message: 'Failed to update group' });
    }
  });



  //removeUserFromGroup
  socket.on('removeUserFromGroup', async (data, callback) => {
    console.log(`removeUserFromGroup`);
    if (!socket.userId || !socket.user) {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Not authenticated' });
    }
    if (socket.user.role !== 'admin') {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Not authenticated' });
    }
    try {
      const { groupId, userId } = data;

      // Validate data
      if (!groupId || !userId) {
        return callback({ success: false, message: 'Missing group ID or user ID' });
      }

      // Check group admin
      const groupA = await db.get('SELECT admin_id FROM groups WHERE id = ?', groupId);

      //Check if the user it's calling is an admin the group.
      if (groupA.admin_id !== socket.user.id) {
        console.log(`removeUserFromGroup - User ID: ${socket.userId} is not an admin of group: ${groupId}`);
        return callback({ success: false, message: 'You are not authorized to remove members from this group.' });
      }
      // Check if the user to be removed is the admin himself
      if (userId === socket.userId) {
        console.log(`removeUserFromGroup - User ID: ${userId} attempted to remove themselves from group: ${groupId}`);
        return callback({ success: false, message: 'Admin cannot remove themselves.' });
      }

      // Remove the user from the group
      const result = await db.run(
        'DELETE FROM group_members WHERE group_id = ? AND user_id = ?',
        [groupId, userId]
      );

      // Check if any rows were actually deleted.
      if (result.changes === 0) {
        console.log('Remove user from group error: User is not a member of the Group');
        return callback({ success: false, message: 'Failed to remove user from group: User is not a member of the group' });
      }

      const userSockets = Array.from(io.sockets.sockets.values())
        .filter(s => s.userId === userId);
      const groupB = await db.get('SELECT id, name FROM groups where id = ?', [groupId]);
      /*const members = await db.all(
        'SELECT user_id FROM group_members WHERE group_id = ?',
        [groupId]
      );*/
      let resultRemove = {
        id: groupB.id,
        name: groupB.name,
        userId: userId,
        message: "It was ejected from group."
      };

      userSockets.forEach(userSocket => {

        userSocket?.emit('groupToWasRemoved', resultRemove);
        userSocket.disconnect(true); // Optionally disconnect the socket as well
      });

      //Call for all to reload the peoples of group
      void await fetchUpdate(groupId, db);
      //Update list if success
      callback({ success: true });
    } catch (error) {
      console.log('Remove user from group error:', error);
      callback({ success: false, message: 'Failed to remove user from group' });
    }
  });

  //addUserToGroup
  socket.on('addUserToGroup', async (data, callback) => {
    console.log(`addUserToGroup`);
    if (!socket.userId || !socket.user || socket.user.role !== 'admin') {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Unauthorized' });
    }
    try {
      const { groupId, userId } = data;

      // Check group admin
      const groupC = await db.get('SELECT admin_id FROM groups WHERE id = ?', groupId);
      //Check if the user it's calling is an admin the group.
      if (groupC.admin_id !== socket.user.id) {
        console.log(`addUserToGroup - User ID: ${socket.userId} is not an admin of group: ${groupId}`);
        return callback({ success: false, message: 'You are not authorized to add members from this group.' });
      }

      // Validate data
      if (!groupId || !userId) {
        return callback({ success: false, message: 'Missing group ID or user ID' });
      }

      //Check if user already part of
      const existingMember = await db.get('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?', [groupId, userId]);
      if (existingMember) {
        console.log(`removeUserToGroup - User ID: ${userId} it's already an member.`)
        return callback({ success: false, message: "User already part of" });

      }

      // Insert the user into the group
      await db.run(
        'INSERT INTO group_members (group_id, user_id) VALUES (?, ?)',
        [groupId, userId]
      );

      //Update the GroupName
      const groupD = await db.get('SELECT id, name, admin_id FROM groups WHERE id = ?', [groupId]);
      //Convert to resualt.
      const members = await db.all(
        'SELECT user_id FROM group_members WHERE group_id = ?',
        [groupId]
      );
      let result = {
        id: groupD.id,
        name: groupD.name,
        adminId: groupD.admin_id,
        members: members.map(m => m.user_id)
      };

      io.emit('newGroupJoined', result);

      //Call for all to reload the peoples of group
      void await fetchUpdate(groupId, db);
      //Update list if success
      callback({ success: true });
    } catch (error) {
      console.log('Add user to group error:', error);
      callback({ success: false, message: 'Failed to add user to group' });
    }
  });



  const fetchUpdate = async (groupId, db) => {

    if (!groupId) {

      console.error("it not found groupId of " + groupId, "Please debug call or view here  on groupId value")
    }

    try { //TODO get socket to update  users in here

      // Use io.to to target the group's room directly
      const fetch = io.to(`group:${groupId}`);

      fetch.emit("To_RELOAD_allgroupPeopleNewUSER-" + groupId, true);  // Emit to all sockets in the room

      console.warn(`update of list is for that Group Id:  ->${groupId}`) //debug the new list of group

      return console.log("update was OK-> " + groupId)
    } catch (_) {
      return console.error(_)

    }

  };

  // Search users
  socket.on('searchUsers', async (data, callback) => {
    console.log(`searchUsers`);
    if (!socket.userId) {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Not authenticated' });
    }

    try {
      const { query } = data;

      // Search users
      const users = await db.all(
        'SELECT id, email, name, role, is_blocked, created_at FROM users WHERE (name LIKE ? OR email LIKE ?) AND role != ?',
        [`%${query}%`, `%${query}%`, 'admin']
      );


      //  user IDs of members in a group
      callback({
        success: true,
        data: users.map(user => ({
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          isBlocked: user.is_blocked === 1,
          createdAt: user.created_at
        }))
      });
    } catch (error) {
      console.log('Search all users error:', error);
      callback({ success: false, message: 'Failed to search users' });
    }
  });
  // Create group
  socket.on('createGroup', async (data, callback) => {
    console.log(`createGroup`);
    if (!socket.userId) {
      console.log('Not authenticated');
      return callback({ success: false, message: 'Not authenticated' });
    }

    try {
      const { name, adminId, members } = data;
      const groupId = Date.now().toString();
      const createdAt = new Date().toISOString();

      // Insert the group
      await db.run(
        'INSERT INTO groups (id, name, admin_id, created_at) VALUES (?, ?, ?, ?)',
        [groupId, name, adminId, createdAt]
      );

      // Add admin as a member
      if (!members.includes(adminId)) {
        members.push(adminId);
      }

      // Add members to the group
      for (const memberId of members) {
        await db.run(
          'INSERT INTO group_members (group_id, user_id) VALUES (?, ?)',
          [groupId, memberId]
        );

      }

      //Emit to each Users that will part of from the group
      for (const memberId of members) {
        const userSockets = Array.from(io.sockets.sockets.values()).filter(s => s.userId === memberId);
        const groupD = await db.get('SELECT id, name, admin_id FROM groups where id = ?', [groupId]);
        const members = await db.all(
          'SELECT user_id FROM group_members WHERE group_id = ?',
          [groupId]
        );
        let result = {
          id: groupD.id,
          name: groupD.name,
          adminId: groupD.admin_id,
          members: members.map(m => m.user_id)
        };

        userSockets.forEach(userSocket => {
          userSocket?.emit('newGroupJoined', result);

        });

      } //For send information for each.
      //Call for all to reload the peoples of group
      void await fetchUpdate(groupId, db);

      callback({ success: true });
    } catch (error) {
      console.log('Create group error:', error);
      callback({ success: false, message: 'Failed to create group' });
    }
  });

  // ===== CHAT FUNCTIONALITY =====

  // Join group (room) - Simplified to only join the room
  socket.on('joinGroup', async (data) => {
    console.log(`joinGroup event received for socket ID: ${socket.id}, userId: ${socket.userId}`);
    if (!socket.userId) return;

    const { groupId } = data;
    console.log(`joinGroup - User ${socket.userId} joining group: ${groupId}`);
    socket.join(`group:${groupId}`); // Join room
    console.log(`joinGroup - User ${socket.userId} joined room group:${groupId}`);
  });

  // Leave group (room)
  socket.on('leaveGroup', (data) => {
    console.log(`leaveGroup`);
    if (!socket.userId) return;

    const { groupId } = data;
    socket.leave(`group:${groupId}`); // Leave room
  });

  // Send group message
  socket.on('sendGroupMessage', async (data, callback) => {
    console.log(`sendGroupMessage`);
    if (!socket.userId) {
      console.log('Not authenticated');
      return callback && callback({ success: false, message: 'Not authenticated' });
    }

    try {
      const { groupId, message } = data;
      const messageId = Date.now().toString();
      const timestamp = new Date().toISOString();
      const { senderId, content, type } = message;

      // Save the message to the database
      // await db.run(
      // Save the message to the database
      // await db.run(
      //   'INSERT INTO messages (id, group_id, sender_id, content, timestamp, type) VALUES (?, ?, ?, ?, ?, ?)',
      //   [messageId, groupId, senderId, content, timestamp, type]
      // ));

      // Fetch the message from the database to ensure consistency
      // const savedMessage = await db.get(
      //   'SELECT id, group_id, sender_id, content, timestamp, type FROM messages WHERE id = ?',
      //   messageId
      // );

      // Emit the message to all clients in the group
      io.to(`group:${groupId}`).emit(`groupMessages:${groupId}`, [savedMessage]);

      if (callback) {
        callback({ success: true });
      }
    } catch (error) {
      console.log('Send group message error:', error);
      if (callback) {
        callback({ success: false, message: 'Failed to send message' });
      }
    }
  });

  // ===== TYPING INDICATOR (EXAMPLE) =====

  socket.on('typing', (data) => {
    if (!socket.userId) return;
    const { groupId, isTyping } = data;
    socket.to(`group:${groupId}`).emit('typing', {
      userId: socket.userId,
      userName: socket.user.name,
      isTyping
    });
  });

  // ===== REALTIME AUDIO (WEBRTC SIGNALING) =====

  socket.on('joinAudioRoom', (data) => {
    const { groupId } = data;
    socket.join(`audioRoom:${groupId}`);

    // Notify existing users in the room
    socket.to(`audioRoom:${groupId}`).emit('userJoined', { socketId: socket.id });
  });

  socket.on('offer', (data) => {
    socket.to(data.targetSocketId).emit('offer', {
      sdp: data.sdp,
      socketId: socket.id,
    });
  });

  socket.on('answer', (data) => {
    socket.to(data.targetSocketId).emit('answer', {
      sdp: data.sdp,
      socketId: socket.id,
    });
  });

  socket.on('iceCandidate', (data) => {
    socket.to(data.targetSocketId).emit('iceCandidate', {
      candidate: data.candidate,
      sdpMid: data.sdpMid,
      sdpMLineIndex: data.sdpMLineIndex,
      socketId: socket.id,
    });
  });

  // Disconnect
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Initialize and start server
async function startServer() {
  console.log('Starting server...');
  try {
    await initializeDatabase();

    const PORT = process.env.PORT || 3000;
    server.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  } catch (error) {
    console.log('Failed to start server:', error);
    process.exit(1);
  }
}


startServer();
