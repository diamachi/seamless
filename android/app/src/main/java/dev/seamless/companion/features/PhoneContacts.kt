package dev.seamless.companion.features

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract
import org.json.JSONArray
import org.json.JSONObject

internal object PhoneContacts {
    fun read(context: Context): List<JSONObject> {
        require(context.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            "Allow Contacts access on the phone first"
        }
        val contacts = mutableListOf<JSONObject>()
        val columns = arrayOf(ContactsContract.CommonDataKinds.Phone._ID,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER)
        context.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, columns, null, null,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC")?.use { cursor ->
            while (cursor.moveToNext() && contacts.size < 5000) {
                val number = cursor.getString(2).orEmpty().take(80)
                if (number.isBlank()) continue
                contacts.add(JSONObject().put("id", cursor.getLong(0).toString())
                    .put("name", cursor.getString(1).orEmpty().take(200)).put("number", number))
            }
        }
        return contacts
    }
}
