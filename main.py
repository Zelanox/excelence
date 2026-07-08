import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import pandas as pd
import json
import os

class ExcelViewer:
    def __init__(self, root):
        self.root = root
        self.root.title("التقيل للعرض و التعديل")
        self.root.geometry("900x600")

        self.df = None
        self.filename = None

        # ----------------- memory ------------------
        self.config_file = "viewer_config.json"

        # ---------------- Top Frame ----------------
        top = tk.Frame(root)
        top.pack(fill="x", padx=5, pady=5)

        tk.Button(top, text="فتح ملف اكسيل", command=self.open_file).pack(side="left")

        tk.Label(top, text="بحث").pack(side="left", padx=(20,5))

        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", self.live_search)

        search_entry = tk.Entry(top, textvariable=self.search_var, width=30)
        search_entry.pack(side="left")

        tk.Button(top, text="عرض الكل", command=self.refresh_tree).pack(side="left", padx=5)

        tk.Button(top, text="إضافة صف", command=self.add_row).pack(side="left", padx=5)

        tk.Button(top, text="حذف صف", command=self.delete_row).pack(side="left", padx=5)

        tk.Button(top, text="ترتيب", command=self.sort_dialog).pack(side="left", padx=5)

        tk.Button(top, text="حفظ", command=self.save_file).pack(side="right")

        # ---------------- Treeview ----------------
        frame = tk.Frame(root)
        frame.pack(fill="both", expand=True)

        self.tree = ttk.Treeview(frame)
        self.tree.pack(side="left", fill="both", expand=True)

        vsb = ttk.Scrollbar(frame, orient="vertical", command=self.tree.yview)
        vsb.pack(side="right", fill="y")

        hsb = ttk.Scrollbar(root, orient="horizontal", command=self.tree.xview)
        hsb.pack(fill="x")

        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

        self.tree.bind("<Double-1>", self.edit_cell)

        # ----Treeview style ----
        style = ttk.Style()

        style.configure(
            "Treeview",
            font=("Segoe UI", 10),
            rowheight=28
        )

        style.configure(
            "Treeview.Heading",
            font=("Segoe UI", 10, "bold")
        )

        style.map(
            "Treeview",
            background=[("selected", "#4A90E2")]
        )

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.load_last_file()

    # ---------------- Open ----------------
    def open_file(self):
        filename = filedialog.askopenfilename(
            filetypes=[("Excel files", "*.xlsx")]
        )

        if not filename:
            return

        self.filename = filename
        self.save_config()
        self.df = pd.read_excel(filename)

        self.refresh_tree()

    # ------------- row formatting -------------
    def save_config(self):
        with open(self.config_file, "w") as f:
            json.dump({"last_file": self.filename}, f)


    def load_last_file(self):
        if not os.path.exists(self.config_file):
            return

        try:
            with open(self.config_file, "r") as f:
                data = json.load(f)

            filename = data.get("last_file")

            if filename and os.path.exists(filename):
                self.filename = filename
                self.df = pd.read_excel(filename)
                self.refresh_tree()

        except Exception:
            pass


    # ---------------- Display ----------------
    def refresh_tree(self, dataframe=None):

        if dataframe is None:
            dataframe = self.df

        if dataframe is None:
            return

        self.tree.delete(*self.tree.get_children())

        self.tree["columns"] = list(dataframe.columns)
        self.tree["show"] = "headings"

        for col in dataframe.columns:
            self.tree.heading(col, text=col, anchor="center")

            # Longest value in this column (limited to 20 characters)
            max_len = min(
                dataframe[col]
                    .fillna("")          # Replace NaN with empty strings
                    .astype(str)
                    .apply(len)
                    .max(),
                20
            )

            # Calculate a reasonable width
            width = max(
                100,                # Minimum width
                len(str(col)) * 12, # Header width
                max_len * 8         # Content width
            )

            self.tree.column(
                col,
                width=width,
                minwidth=80,
                stretch=True,
                anchor="center"
            )
        
        self.create_stripes(dataframe)

    def create_stripes(self, dataframe):

        for display_index, (real_index, row) in enumerate(dataframe.iterrows()):

            tag = "even" if display_index % 2 == 0 else "odd"

            self.tree.insert(
                "",
                "end",
                iid=str(real_index),      # Keep the real DataFrame index
                values=list(row),
                tags=(tag,)
            )

        self.tree.tag_configure("even", background="#FFFFFF")
        self.tree.tag_configure("odd", background="#A0ECF3")

    # ---------------- Search ----------------
    def live_search(self, *args):
        """Called automatically whenever the search text changes."""
        if self.df is None:
            return

        text = self.search_var.get().strip().lower()

        if text == "":
            self.refresh_tree()
            return

        mask = self.df.astype(str).apply(
            lambda row: row.str.lower().str.contains(text, na=False).any(),
            axis=1
        )

        self.refresh_tree(self.df[mask])


    def search(self):
        # Optional: keep compatibility if called elsewhere
        self.live_search()

    # ------------- Add Row ----------------

    def add_row(self):

        if self.df is None:
            return

        new_row = {}

        for col in self.df.columns:
            new_row[col] = ""

        self.df.loc[len(self.df)] = new_row

        self.refresh_tree()

        new_id = str(len(self.df) - 1)

        self.tree.selection_set(new_id)
        self.tree.focus(new_id)

    # ---------------- Edit ----------------
    def edit_cell(self, event):

        item = self.tree.focus()

        column = self.tree.identify_column(event.x)

        if not item or not column:
            return

        col_index = int(column.replace("#","")) - 1

        x, y, w, h = self.tree.bbox(item, column)

        old_value = self.tree.item(item)["values"][col_index]

        entry = tk.Entry(self.tree)

        entry.insert(0, old_value)
        entry.place(x=x, y=y, width=w, height=h)

        entry.focus()

        def save_edit(event=None):
            new_value = entry.get()

            dtype = self.df.dtypes.iloc[col_index]

            try:
                if pd.api.types.is_integer_dtype(dtype):
                    new_value = int(new_value)

                elif pd.api.types.is_float_dtype(dtype):
                    new_value = float(new_value)

            except ValueError:
                messagebox.showerror(
                    "قيمة غير صالحة",
                    f"من فضلك ادخل قيمة {dtype} صالحة."
                )
                return

            values = self.tree.item(item)["values"]
            values[col_index] = new_value

            self.tree.item(item, values=values)

            real_index = int(item)
            self.df.iat[real_index, col_index] = new_value

            entry.destroy()

        entry.bind("<Return>", save_edit)
        entry.bind("<FocusOut>", save_edit)

    def sort_dialog(self):

        if self.df is None:
            return

        window = tk.Toplevel(self.root)
        window.title("ترتيب مخصص")

        columns = [""] + list(self.df.columns)

        col_vars = []
        order_vars = []

        for i in range(3):

            tk.Label(
                window,
                text=f"Level {i+1}"
            ).grid(row=i*2, column=0, padx=10, pady=(10,0), sticky="w")

            col_var = tk.StringVar(value="")
            order_var = tk.StringVar(value="تصاعدي")

            ttk.Combobox(
                window,
                textvariable=col_var,
                values=columns,
                state="readonly",
                width=20
            ).grid(row=i*2+1, column=0, padx=10, pady=5)

            ttk.Combobox(
                window,
                textvariable=order_var,
                values=["تصاعدي", "تنازلي"],
                state="readonly",
                width=15
            ).grid(row=i*2+1, column=1, padx=10, pady=5)

            col_vars.append(col_var)
            order_vars.append(order_var)

        def apply_sort():

            sort_columns = []
            ascending = []

            for col_var, order_var in zip(col_vars, order_vars):

                column = col_var.get()

                if column == "":
                    continue

                sort_columns.append(column)
                ascending.append(order_var.get() == "تصاعدي")

            if not sort_columns:
                return

            # Prevent duplicate columns
            if len(sort_columns) != len(set(sort_columns)):
                messagebox.showerror(
                    "ترتيب",
                    "من فضلك اختر أعمدة مختلفة."
                )
                return

            # Try converting numeric columns automatically
            for column in sort_columns:
                try:
                    self.df[column] = pd.to_numeric(self.df[column])
                except Exception:
                    pass

            self.df.sort_values(
                by=sort_columns,
                ascending=ascending,
                inplace=True,
                ignore_index=True
            )

            self.refresh_tree()
            window.destroy()

        ttk.Button(
            window,
            text="ترتيب",
            command=apply_sort
        ).grid(row=7, column=0, columnspan=2, pady=15)

    # -------------- Delete ----------------
    def delete_row(self):

        selected = self.tree.selection()

        if not selected:
            return

        index = int(selected[0])

        self.df = self.df.drop(index).reset_index(drop=True)

        self.refresh_tree()

    # ---------------- Save ----------------
    def save_file(self):

        if self.df is None:
            return

        self.df.to_excel(self.filename, index=False)

        messagebox.showinfo("تم الحفظ", "تم الحفظ بنجاح.")

    def on_close(self):

        try:
            if self.df is not None and self.filename:
                self.df.to_excel(self.filename, index=False)

        except Exception as e:
            messagebox.showerror("خطأ", f"مقدرناش نحفظ:\n{e}")
            return

        self.root.destroy()


root = tk.Tk()
app = ExcelViewer(root)
root.mainloop()